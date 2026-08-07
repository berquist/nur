# Using NWChem instead of Psi4 in the compute VM tests

Status: **investigated, not implemented.** Parked 2026-08-03.

## Why it came up

The `vm-compute-connects` and `vm-compute-singlepoint` tests need a real QC program on the
worker's `PATH` — `qcfractalcompute` raises

    ValueError: Executor <label> has no available programs

and exits if an executor discovers none (`qcfractalcompute/compute_manager.py:148-152`), so an
empty `executor.programs` is not a testable configuration.

Psi4 was chosen, and comes from the `nixos-qchem` flake input. When `nix-qchem.cachix.org` was
not being hit, Psi4's whole closure (CheMPS2, adcc, libint, …) had to be compiled from source,
which is slow. NWChem is in nixpkgs proper (`pkgs.nwchem`, currently 7.2.3, ECL-2.0,
`meta.mainProgram = "nwchem"`), so it would be covered by `cache.nixos.org` and need no extra
substituter at all.

That is the appeal. It is not a drop-in substitution.

## Blocker 1: the harness needs `networkx`, which is not in the closure

QCEngine's NWChem harness reports itself available only if **both** the executable and the
Python module `networkx` are found — `qcengine/programs/nwchem/runner.py:54-84`:

```python
qc  = which("nwchem", return_bool=True, raise_error=raise_error, ...)
dep = which_import("networkx", return_bool=True, raise_error=raise_error,
                   raise_msg="For NWChem harness, please install via `conda install networkx -c conda-forge`.")
return qc and dep
```

`networkx` is in neither package's runtime closure:

```
qcengine          propagatedBuildInputs: msgpack numpy psutil py-cpuinfo pydantic
                                         pydantic-settings pyyaml qcelemental
qcfractalcompute  propagatedBuildInputs: numpy parsl pydantic pydantic-settings
                                         pyyaml qcengine qcportal
```

So `executor.programs = [ pkgs.nwchem ]` alone lands right back on "Executor local_executor has
no available programs" — the failure looks identical to having installed nothing.

Upstream QCEngine does not declare `networkx` as a dependency (it tells you to `conda install`
it), so this is a genuine gap rather than a packaging mistake on our side.

**Fix:** add `networkx` to `dependencies` in `pkgs/qcfractalcompute/default.nix`. That puts it in
the `pythonEnv` the compute module builds from `cfg.package` and places first on the unit's
`PATH` — which is the interpreter that actually performs discovery, since
`AppManager.discover_programs_conda` shells out to `python3 qcengine_list.py` rather than
importing in-process (see the note in `CLAUDE.md`). One line, pure-Python dependency, no need to
touch or fork `qcengine`.

Worth doing on its own merits even if the tests keep using Psi4 — the compute module's
`executor.programs` option advertises `pkgs.nwchem` in its description, and today that
combination silently does not work.

## Blocker 2: nixpkgs builds NWChem for MPI-PR, which needs ≥ 2 ranks

This is the harder one.

`pkgs/by-name/nw/nwchem` (formerly `pkgs/applications/science/chemistry/nwchem`) configures:

```nix
export ARMCI_NETWORK="MPI-PR";
export USE_MPI="y";
```

ARMCI's `MPI-PR` ("progress ranks") back end dedicates one MPI rank per node to communication
progress, leaving the rest for compute. With a single rank there are zero compute ranks and
NWChem aborts during Global Arrays initialisation. nixpkgs' own install check reflects this — it
runs the job with two ranks:

```nix
installCheckPhase = ''
  mpirun -np 2 $out/bin/nwchem $NWCHEM_TOP/QA/tests/h2o/h2o.nw > h2o.out
  grep "Total SCF energy" h2o.out | grep 76.010538
'';
```

QCEngine, however, launches the bare executable unless it has been told to use MPI —
`qcengine/programs/nwchem/runner.py:157-161`:

```python
if config.use_mpiexec:
    nwchemrec["command"] = create_mpi_invocation(which("nwchem"), config)
else:
    nwchemrec["command"] = [which("nwchem")]
```

and `use_mpiexec` is derived, in `qcengine/config.py:326`, as

```python
config["use_mpiexec"] = node.is_batch_node or config["nnodes"] > 1
```

Both are false for a single-node local executor, so NWChem would be launched single-rank and
fail immediately.

> Note: this blocker is reasoned from the derivation and the QCEngine source, **not** observed.
> Nothing here could be run — the Claude Code sandbox cannot reach the nix-daemon, so no VM was
> ever booted. Confirm by actually running a single-rank NWChem before investing in the fix.

### What making it work would take

`get_config` merges `QCENGINE_*` environment variables into the task config
(`read_qcengine_task_environment`, `qcengine/config.py:272-282`) and applies them over the
node-derived values (`config.update(task_config)`, line 331). Caller-supplied values still win
over the environment (line 294), but `qcfractalcompute` does not set either of these, so the
environment route is available:

- `QCENGINE_USE_MPIEXEC=true`
- `QCENGINE_MPIEXEC_COMMAND="mpirun -n {total_ranks} ..."` — `create_mpi_invocation`
  (`qcengine/util.py:34-56`) formats `{nnodes}`, `{ranks_per_node}`, `{total_ranks}` and
  `{cores_per_rank}` into it, then appends the executable. The `NodeDescriptor` validator that
  demands `{ranks_per_node}` be present does not apply on this path, since it bypasses
  `NodeDescriptor`.

Plus, on the NixOS side:

- `mpirun` on the unit's `PATH` — `pkgs.nwchem.passthru.mpi` exposes the exact MPI it was built
  against, so `executor.programs = [ pkgs.nwchem pkgs.nwchem.passthru.mpi ]`.
- `services.qcfractalCompute.executor.coresPerWorker = 2`, because `total_ranks` is
  `nnodes * ncores // cores_per_rank` — with the default `coresPerWorker = 1` you still get one
  rank and the same failure.
- `virtualisation.cores = 2` on the test node so those two ranks have somewhere to run.
- A way to set unit environment variables. The module has no option for this; the test can use
  `systemd.services.qcfractalcompute.environment` directly (NixOS merges it with the module's
  definition), but a real user configuring NWChem would want a proper option — perhaps
  `services.qcfractalCompute.environment` or a dedicated `executor.useMpi`.

### Open questions before implementing

- Does single-rank NWChem from nixpkgs actually fail? (Assumed, unverified — see note above.)
- Does `mpirun` work inside the test VM without extra privileges? OpenMPI often wants
  `--allow-run-as-root`, shared memory, or `--oversubscribe` when ranks exceed cores.
- HF/STO-3G on H2 with `qc_module=False` should route to NWChem's SCF module via
  `germinate.muster_modelchem`; worth confirming the method string maps as expected.
- The basis library is found via the `NWCHEM_BASIS_LIBRARY` default set by `wrapProgram` in the
  nixpkgs derivation — should be fine under systemd, but it is a wrapper-script dependency.

## Recommendation as of parking

Prefer fixing the Psi4 cache path (see the `nixos-qchem` notes in `CLAUDE.md`) over switching QC
codes. NWChem's appeal is entirely "it is in nixpkgs, so it is already cached"; that advantage
disappears the moment it needs a custom MPI launch configuration that nothing upstream exercises.

Blocker 1 (`networkx`) is worth fixing regardless — it is one line and it makes a documented
configuration work.

If NWChem is revisited, the sensible shape is a *third* test rather than a replacement:
`compute-singlepoint` stays on Psi4 as the end-to-end reference, and an NWChem variant covers
the MPI-launch path, which is a genuinely different code path worth its own coverage.
