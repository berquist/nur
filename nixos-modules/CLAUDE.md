# NixOS modules

`nixos-modules/default.nix` exports **paths**, not module functions — NUR requires this, and
paths avoid double-import conflicts.

`qcfractal-server.nix` (`services.qcfractal.*`) and `qcfractal-compute.nix`
(`services.qcfractalCompute.*`) are deliberately independent; neither imports the other.

Conventions both modules follow:

- Config YAML is generated with `lib.generators.toYAML` into the Nix store, then installed into
  `stateDir` at service start. The server installs it **only on first run** (manual edits
  survive); the compute worker re-installs it whenever the generated file differs.
- Secrets never enter the store. `database.passwordFile` / `server.passwordFile` are read in the
  `ExecStart` shell script and exported as `PGPASSWORD` / `QCF_COMPUTE_SERVER__PASSWORD`
  (pydantic-settings maps the latter to `server.password`).
- The server has three units, not two: `qcfractal-init-db` bootstraps, `qcfractal-upgrade-db`
  applies Alembic migrations, `qcfractal` serves. The migration unit is **always defined but only
  `wantedBy` anything when `database.autoUpgrade = true`**, so the default upgrade path is the
  manual `systemctl start qcfractal-upgrade-db.service` that upstream's "after backing up!" message
  asks for. It is ordered after `init-db` because `upgrade-db` refuses on a database that does not
  exist yet, and it needs the config file `init-db` installs. All three units share the
  `runtimeSecrets` preamble — `upgrade-db` validates the full `FractalConfig` before touching the
  database, so it needs the api keys just as much as `start` does.
- `localDB` in the server module means `createLocally && database.host == "/run/postgresql"` —
  the gitea idiom for "peer-authenticated local socket". Assertions enforce that `user ==
  database.user` in that case, and that the socket path is not used with `createLocally = false`.
- The compute module puts `executor.programs` on the unit's `path`; QCEngine discovers QC codes
  by probing `PATH`, so listing a package is all that is needed — no conda env, no `worker_init`.
  **But `PATH` alone discovers nothing — the unit's `environment.PYTHONPATH` is what makes it
  work.** Discovery is out-of-process: `AppManager.discover_programs_conda` runs
  `subprocess.check_output(["python3", …/qcengine_list.py])`, and nixpkgs injects dependencies with
  `site.addsitedir()` *inside* the wrapped script, which does not reach a child process.
  `qcengine_list.py` catches `ImportError` and prints `{}`, so the child yields zero programs and
  the manager dies with `Executor <label> has no available programs` — a message that points at
  `executor.programs` while the fault is the interpreter. Two things that look like fixes and are
  not: putting a python env on `PATH` (the package's own wrapper prepends a bare interpreter that
  wins), and `NIX_PYTHONPATH` (`sitecustomize.py` pops it "to prevent leakage", so children never
  see it). `compute-python-path-for-discovery` guards this.
- **`executor.programs` entries that are Python packages also get appended to `PYTHONPATH`**, each
  as its own `withPackages` env. Discovery is not the reason — a Python-native harness may import
  its program *in-process* even when the calculation runs as a subprocess. `Psi4Harness.found()`
  gets psi4 itself onto `sys.path` by running `psi4 --module` and appending the printed path (which
  works because psi4's launcher handles `--module` before importing anything beyond the stdlib, so
  stderr stays empty — the fallback requires `(stdout) and (not stderr) and rc == 0`), but that
  directory carries none of psi4's *dependencies*. Harmless until QCEngine 0.50.0 replaced
  0.50.0rc2's version comparison with `inspect.signature(psi4.driver.p4util.state_to_atomicinput)`,
  making `compute()` import psi4 unconditionally: the import now reaches `driver_nbody.py` and dies
  on `No module named 'qcmanybody'`. QCEngine turns that into an execution error, so the manager
  stays up and *every claimed task errors* — it reads as a bad calculation, not a missing module.
  Do not merge the program envs into `pythonEnv`: `pkgs.qchem.*` comes from a different nixpkgs
  instantiation, so the two closures collide on numpy, pydantic, qcelemental and qcengine.
  Appending keeps those resolving to `pythonEnv`, which is what the `psi4 --module` fallback
  already did.
- **`pkgs.qchem.psi4` is a `toPythonApplication`, so `psi4.pythonModule` is `false`, not an
  interpreter.** NixOS-QChem's `overlay.nix` builds it as
  `toPythonApplication python3.pkgs.psi4`, and that wrapper sets `pythonModule = false` to mark the
  program as *not* importable as a library. So `p ? pythonModule` is true while
  `p.pythonModule.pythonVersion` is missing, and any filter written the obvious way silently drops
  psi4 and leaves `PYTHONPATH` byte-identical — the VM test then rebuilds to the *same derivation
  hash*, which looks exactly like the edit never landed. Test `lib.isDerivation p.pythonModule`,
  and take the application form's closure and interpreter from `requiredPythonModules` (47 entries
  for psi4; the interpreter is its one element with `pythonVersion`/`withPackages`).
- Psi4 itself is deliberately absent from the env it gets: `found()`'s `psi4 --module` fallback
  already supplies it. Verified by running the HF/STO-3G singlepoint with psi4's own site-packages
  removed from `PYTHONPATH` — still -1.1167383 Eh.

Both of the above were checked by running the real code against the store paths rather than by
reading it, which is worth doing before touching this again — no nix-daemon is needed:

```sh
# reconstruct the manager's sys.path from its wrapper, then run discovery
PYTHONPATH=<those dirs> PATH=<bare python>/bin:<psi4>/bin python3 …/run_scripts/qcengine_list.py
# bare  -> {}
# with  -> {"psi4": "1.10", "qcengine": "0.50.0rc2"}
```

A full HF/STO-3G H2 singlepoint run the same way returns -1.11674 Eh, which is where the bracket
in the `compute-singlepoint` VM test comes from.
