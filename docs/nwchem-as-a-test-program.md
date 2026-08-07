# Using NWChem instead of Psi4 in the compute VM tests

Status: **investigated, not implemented.** Parked 2026-08-03.

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
