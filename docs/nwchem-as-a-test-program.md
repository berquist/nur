# Using NWChem instead of Psi4 in the compute VM tests

Status: **both blockers fixed, 2026-08-07.** NWChem now works as a compute program; the VM
tests still use Psi4 as the end-to-end reference. What was done, and what is still open, is at
the bottom under "Resolution".

The compute VM tests need a real QC program on the worker's `PATH` — `qcfractalcompute` raises
`ValueError: Executor <label> has no available programs` and exits if an executor discovers none
(`qcfractalcompute/compute_manager.py:148-152`). Psi4 fills that role today, via the
`nixos-qchem` flake input. NWChem is in nixpkgs proper, so it would be covered by
`cache.nixos.org` and need no extra substituter. That is the whole appeal, and it does not
survive contact with two blockers.

## Blocker 1: the harness needs `networkx`, which is not in the closure

QCEngine's NWChem harness reports itself available only if **both** the executable and the
Python module `networkx` are found (`qcengine/programs/nwchem/runner.py:54-84`) — and `networkx`
is in neither `qcengine`'s nor `qcfractalcompute`'s runtime closure. Upstream QCEngine does not
declare it as a dependency (it tells you to `conda install` it), so this is a genuine gap rather
than a packaging mistake here.

So `executor.programs = [ pkgs.nwchem ]` lands right back on "has no available programs", a
failure indistinguishable from having installed nothing.

**Fix: add `networkx` to `dependencies` in `pkgs/qcfractalcompute/default.nix`.** That puts it
in the `pythonEnv` the compute module exports as `PYTHONPATH`, which is the interpreter that
actually performs discovery. One line, pure Python, no fork of `qcengine`.

This is worth doing **whether or not the tests ever switch**: the compute module's
`executor.programs` option advertises `pkgs.nwchem` in its description, and today that
combination silently does not work.

## Blocker 2: nixpkgs builds NWChem for MPI-PR, which needs ≥ 2 ranks

`pkgs/by-name/nw/nwchem` sets `ARMCI_NETWORK="MPI-PR"`. That back end dedicates one MPI rank per
node to communication progress, so a single rank leaves zero compute ranks and NWChem aborts
during Global Arrays initialisation — nixpkgs' own `installCheckPhase` runs the job with
`mpirun -np 2`.

QCEngine launches the bare executable unless told otherwise: `use_mpiexec` is
`node.is_batch_node or config["nnodes"] > 1` (`qcengine/config.py:326`), both false for a
single-node local executor.

> Reasoned from the derivation and the QCEngine source, **not** observed — nothing here could be
> run at the time. Confirm by actually running a single-rank NWChem before investing in a fix.

Making it work would need `QCENGINE_USE_MPIEXEC` / `QCENGINE_MPIEXEC_COMMAND` in the unit's
environment (the module has no option for that), `mpirun` on the worker's `PATH`
(`pkgs.nwchem.passthru.mpi`), `coresPerWorker = 2` so `total_ranks` comes out above one, and
`virtualisation.cores = 2` on the test node. Open questions: whether single-rank NWChem really
fails, and whether `mpirun` works inside the test VM without `--allow-run-as-root` or
`--oversubscribe`.

## Recommendation as of parking

Prefer keeping Psi4 and fixing its cache path. NWChem's appeal is entirely "already cached", and
that disappears the moment it needs an MPI launch configuration nothing upstream exercises.

If NWChem is revisited, the sensible shape is a *third* test rather than a replacement:
`compute-singlepoint` stays on Psi4 as the end-to-end reference, and an NWChem variant covers
the MPI-launch path, which is a genuinely different code path worth its own coverage.

## Resolution

Both blockers are fixed, and the recommendation above still stands: Psi4 remains the end-to-end
reference, NWChem is now a *supported* program rather than a replacement for it.

- Blocker 1: `networkx` is a dependency of `pkgs/qcfractalcompute/default.nix`. That package's
  closure is what the compute module turns into `PYTHONPATH`, which is the interpreter
  discovery actually runs in.
- Blocker 2: `services.qcfractalCompute.executor.mpi.{enable,package,command}` in
  `nixos-modules/qcfractal-compute.nix`. `enable` sets `QCENGINE_USE_MPIEXEC` and
  `QCENGINE_MPIEXEC_COMMAND` on the unit, `package` puts `mpirun` on its PATH, and assertions
  reject `enable` without a package or with `coresPerWorker < 2`.

  It also sets `QCENGINE_NCORES` to `coresPerWorker`, which was not in the plan above. The
  startup probe runs `get_version()` with no task config, so it sizes itself from the whole
  node — on a 64-core host that is a version check on 128 ranks. Real tasks pass `ncores`
  explicitly (`qcfractalcompute/apps/qcengine.py`), and a caller-supplied value beats the
  environment, so the cap reaches only the probe.

The env-var route was verified by reading the installed QCEngine 0.50.0 rather than the docs:
`read_qcengine_task_environment` (config.py:272) lower-cases every `QCENGINE_*` name into the
task config, `config.update(task_config)` (line 331) applies it over the node-derived values,
and `use_mpiexec` is consulted only by `programs/nwchem/runner.py` and `programs/mrchem.py`.

Still unverified, and it is what a VM test would settle: whether `mpirun -n 2` runs at all
inside a test VM under this unit's sandboxing (`ProtectSystem=strict`, `PrivateTmp`,
`RestrictAddressFamilies`), and whether HF/STO-3G maps onto NWChem's SCF module as expected.
`personal-cluster-config`'s `hosts/meyeri/qcarchive-test.nix` exercises exactly that against a
real deployment; an `compute-nwchem-singlepoint` here would be the version that guards the
module.
