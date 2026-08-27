# Worklog

One file per session that amounted to a plan or a multi-step task, newest first. Each holds the
prompts verbatim, the plan inlined, what changed, and — most usefully — what was tried and
abandoned.

Grep the `touches:` globs in the front matter before changing a file, to find the history behind
it.

- [2026-08-26 the pollution lottery](2026-08-26-pollution-lottery.md) — a green `ci-matrix` that never rebuilt the failing derivation; six more `aiida_profile_clean` guards found by scanning for the shape instead of waiting for the 1-in-128 draw; `tests/aiida/ordering.nix` turns each pair into a build, with `--arg unguard true` as the control that proves it is not green for nothing.
- [2026-08-25 ci-matrix green](2026-08-25-ci-matrix-green.md) — eight AiiDA failures, each hiding the next, and a QCFractal worker importing a Psi4 built for another Python. An RLock cannot fix state two greenlets reach; `--only-rerun` cannot fix state that outlives the retry.
- [2026-08-18 ci-build nixpkgs repairs](2026-08-18-ci-build-nixpkgs-repairs.md) — `scripts/demux-build-log.sh` untangles a `--keep-going` log; two nixpkgs bugs behind it — rdkit ships no `.dist-info`, octopus gets the C netcdf but wants `netcdffortran`. Octopus hides its errors in files the input names.
- [2026-08-17 cheminformatics family](2026-08-17-cheminformatics-family.md) — 16 new packages and two overlays; found that `python3Packages` is not `python3.pkgs`, so harmonwig's cclib had never resolved. `git archive | nix hash path` gives fetchFromGitHub hashes offline.
- [2026-08-17 AiiDA ecosystem](2026-08-17-aiida-ecosystem.md) — 20 new packages, `services.aiida`, and two test suites; every hash but five recovered offline from `uv.lock`, nothing built yet.
