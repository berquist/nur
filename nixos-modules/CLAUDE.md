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
- Psi4 needs nothing extra despite being a Python-native harness. `Psi4Harness.found()` wants both
  `which("psi4")` and `which_import("psi4")`, but when only the executable is present it recovers by
  running `psi4 --module` and appending the printed path to `sys.path`. That works here because
  psi4's launcher handles `--module` before importing anything beyond the stdlib, so stderr stays
  empty — the fallback requires `(stdout) and (not stderr) and rc == 0`. Actual calculations run as
  `psi4 --qcschema` subprocesses, so the psiapi path is never exercised.

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
