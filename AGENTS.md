# AGENTS.md

Guidance for working in this repository.

## What this is

berquist's personal [NUR](https://github.com/nix-community/NUR) repository, built from
`nur-packages-template`. It holds five unrelated bodies of work:

- the **QCArchive/QCFractal ecosystem** — Python packages (`qcportal`, `qcfractal`,
  `qcfractalcompute`, `qcarchivetesting`, `parsl`) plus two NixOS service modules.
- the **AiiDA ecosystem** — `aiida-core`, twenty plugins, the thirty-odd dependencies of those
  that nixpkgs does not carry, and one NixOS service module. Six wrap a quantum chemistry or
  materials program (`aiida-cp2k`, `aiida-gaussian`, `aiida-orca`, `aiida-octopus`,
  `aiida-psi4`, `aiida-quantumespresso`); six more wrap another simulation code (`aiida-ase`,
  `aiida-gromacs`, `aiida-lammps`, `aiida-nwchem`, `aiida-siesta`, `aiida-wannier90`); two
  build workflows on top of those (`aiida-phonopy`, `aiida-wannier90-workflows`); and six are
  infrastructure rather than a wrapper — `aiida-shell`, which runs an arbitrary command under
  provenance and so reaches the ~60 programs already in `pkgs.qchem.*` without a plugin each,
  `aiida-pythonjob` and `aiida-workgraph`, which do the same for Python functions and for whole
  graphs of them, `aiida-submission-controller`, `aiida-restapi`, and `aiida-firecrest`, whose
  transport runs jobs through a FirecREST endpoint rather than over SSH.
  That module offers both of aiida-core's read-write storage plugins: `core.psql_dos` by
  default, and `core.sqlite_dos` — which needs no service at all — behind
  `services.aiida.storage.backend`.
  Together with QCArchive this is the bulk of the repo. It shares the `python313` pin with
  QCArchive and nothing else; the two overlays are separate so that a consumer can take one
  without the other's closure.
- the **cheminformatics family** — `morfeus-ml`, `qmzyme`, `dough`, `dbstep`, `aqme`, `ccreg`,
  `digichem-core`, `metallogen`, `xyzrender`, plus the dependencies of those that
  nixpkgs lacks (`mdanalysis`, `griddataformats`, `mda-xdrlib`, `mrcfile`, `basis-set-exchange`,
  `colour-science`, `configurables`, `openprattle`, `lwreg`, `xyzgraph`, `graphrc`). Two overlays
  rather than one, split on whether the package needs cclib — see the cclib split below.
  `graphrc` is the awkward one: a dependency that cclib forces to be a top-level attribute
  anyway, so it is the sole member of `cclibDependencies` in `tests/cheminformatics`.
- **dotdrop** — a standalone dotfile-manager CLI, not in nixpkgs. It shares nothing with the
  above and is deliberately kept separate: its own overlay, its own test subdirectory, and the
  default `python3` rather than the 3.13 pin.
- **harmonwig** — likewise a standalone CLI.
- the **chemtools family** — `wignernj`, `strainjedi`, `sella`, `molara`, `moltui`, and the
  `chemfiles` C++ library with its Python binding, plus two dependencies that stay internal:
  `pyrr` (which nixpkgs *removed*, so there is no attribute to fall back to) and the `trexio`
  Python binding. These share no closure with each other or with anything above; they are one
  overlay rather than several because each would otherwise be an overlay attribute holding a
  single `callPackage`. `moltui` is a top-level attribute rather than a package-set member, like
  dotdrop and harmonwig — see the table below. Two names in here collide with something else:
  `chemfiles` (ours, C++ versus Python) and `trexio` (nixpkgs', C library versus Python), and
  the second is the dangerous one.
- the **materials family** — `custodian`, `fireworks`, `qtoolkit`, `maggma`, `jobflow`,
  `jobflow-remote`, `pubchempy`, `pymatgen-io-validation`, `emmet-core`, the three
  `pymatgen-analysis-{alloys,defects,diffusion}` add-ons, `optimade`, `lobsterpy`, `matgl`, and
  `atomate2`, `matcalc`, `quacc`, `matminer`, `redun`, `phono3py`, `mp-api`, `vise`, `shakenbreak`,
  and both halves of upstream
  pymatgen's 2026 split, `pymatgen-core` and `pymatgen`. Plus a dozen carried for a dependant
  alone and not re-exported: `mongomock-persistence` (fireworks'), `mongomock-ng` (maggma's),
  `mp-pyrho` (`pymatgen-analysis-defects`'), `mendeleev` (`lobsterpy[featurizer]`'s), `rootstock`
  (`quacc[mlip]`'s), `sevenn` (`matcalc[sevennet]`'s), `maml` (`matcalc[maml]`'s), `deepmd-kit`
  (`matcalc[deepmd]`'s) with `dargs` and `dpdata` under it — and `parmed` and
  `dpdata-plugin-test` under *that*, both for dpdata's check phase alone —
  `fairchem-core`
  (`matcalc[fairchem]`'s and `quacc[mlip]`'s) with `clusterscope` and
  `ase-db-backends` under it and `fairchem-data-{oc,omat,omol}` beside it
  (`quacc[fairchem]`'s, three more distributions out of the same monorepo), the
  `quacc[defects]` cluster's lower layers — `doped` and `pydefect` and `hiphive`,
  `trainstation` (hiPhive's one gap), `cmcrameri` and `matplotlib-label-lines` (doped's plotting,
  the latter pydefect's too) — `tensorpotential` (`matcalc[grace]`'s, and **the one unfree package here**;
  see "Deferred packaging"), and `monty`, a
  backport that exists only because `pymatgen-core` needs a version no channel here ships yet.
  **This is the one overlay that replaces packages nixpkgs already has** — `pymatgen`, because
  upstream split it and the two layouts cannot coexist, `monty` on the legs that are behind,
  `torchtnt`, which is simply broken against setuptools 83, and `py-lmdb`, pinned *down* to 1.7.3
  because 2.0 forbids opening one environment path twice and three packages here depend on doing so.
  Taking `overlays.materials` means taking both; see the cclib-style discussion at the overlay
  itself and in `pkgs/pymatgen-core/default.nix`. One member is not a Python package at all:
  `enumlib`, the Fortran `enum.x` / `makestr.x` that pymatgen's `EnumlibAdaptor` shells out to,
  which is a top-level `callPackage` like the chemtools overlay's `chemfiles`. See "Deferred
  packaging" below for what is still gated.

### The cclib split

cclib is in neither nixpkgs nor NixOS-QChem and upstream ships its own flake, so that is where it
comes from. `overlays/` holds plain `final: prev:` functions and is imported **without flakes** by
`default.nix`, `overlay.nix` and `ci.nix`, so it cannot reach a flake input. Ten packages need
cclib and each takes it as a defaulted `cclib ? null` argument. `rg -l 'cclib \? null' pkgs/` is
the list; keep this table in step with it:

| Package | Where it lives | Buildable through |
|---|---|---|
| `harmonwig` | `overlays.harmonwig` | the flake only |
| `dbstep`, `aqme`, `ccreg`, `digichem-core`, `metallogen`, `xyzrender` | `overlays.cheminformatics-cclib` | the flake only |
| `graphrc` | `overlays.cheminformatics-cclib` | the flake only, and never a NUR attribute — see below |
| `aiida-gaussian` | `overlays.aiida` | **neither**, today |
| `qmzyme` | `overlays.cheminformatics` | both — its cclib use is test-only and lazy |

The first seven are `meta.broken` on the NUR path and replaced in `flake.nix`'s `packages` by the
ones from `cclibPkgs`. `graphrc` carries the same `broken = cclib == null;` but is not in that
override, because `default.nix` never re-exports it — it reaches the flake through
`legacyPackages` and `python313Packages` alone. `qmzyme` is the one dependant with no
`meta.broken` at all; it skips a test instead. And `aiida-gaussian` is broken everywhere: a plugin
must come from the same package set as its `aiida-core`, and putting the `aiida` overlay into
`cclibPkgs` would rebuild that whole closure against NixOS-QChem's nixpkgs rather than ours.

Note that cclib's overlay overrides the **top-level `python3` attribute** and nothing else, so
`final.python3.pkgs` is the only set that has it. Two traps follow, and both are silent — a
`callPackage` whose `cclib` argument is defaulted just leaves it `null`:

- `final.python313Packages`, which every other family here uses, is a different set that never
  sees cclib. So `overlays.cheminformatics-cclib` and `overlays.harmonwig` are top-level
  `callPackage`s rather than `pythonPackagesExtensions` members.
- **`final.python3Packages` is not `final.python3.pkgs`.** nixpkgs defines
  `python3Packages = dontRecurseIntoAttrs python314Packages` — an alias to the *versioned* set,
  which cclib's overlay does not touch. Spelling it `python3Packages` yields a package that is
  `meta.broken` even on the flake path, with nothing to say so. Always `final.python3.pkgs`.

The `nixos-qchem` flake input supplies quantum-chemistry programs as `pkgs.qchem.*` and is
re-exported as `overlays.qchem`.

### Reusing NixOS-QChem

**When a package here needs a program NixOS-QChem already carries, take theirs. Do not package
it, and do not package it merely because nixpkgs lacks it.** That input exists to be the source
of quantum chemistry and molecular-simulation programs for this repository; duplicating one is a
second derivation to maintain, a second version to keep in step, and a cache miss where their
Hydra already has a build. `package_list.json` at the root of the `nixos-qchem` checkout is the
list to check first — around 60 programs, `qchem.<name>` each.

The constraint is where the reference can be written, not whether to write it. `overlays/` holds
plain `final: prev:` functions and is imported **without flakes** by `default.nix`, `overlay.nix`
and `ci.nix`, so it cannot reach the input — the same wall as the cclib split above. So a
dependant takes a defaulted argument, the overlay resolves it with
`final.<name> or final.qchem.<name> or null`, and the derivation runs fewer tests (or is
`meta.broken`) when it comes back null. Three worked examples, and the oldest is the one to copy:
`pkgs/aqme` takes `xtb` and `crest` that way, `pkgs/postopus` takes `octopus`, and
`pkgs/fairchem-data-oc` takes `packmol`. They differ only in which way the usual case falls —
nixpkgs has xtb and octopus, so those nearly always resolve, while it has neither crest nor
packmol, so those are null on every path but the flake's.

Where a check needs the real program, `flake.nix` selects it from `qchemPkgs` — the same
instantiation `psi4` and `cclibPkgs` come from — and exposes the result as a `checks` entry
guarded on `system == "x86_64-linux"`, which is the only system NixOS-QChem's flake has outputs
for. `checks.fairchem-data-oc` is the pattern; `checks.harmonwig` is the older one.

## Where the explanations live

Every non-obvious decision here is commented **at the code it governs**, because that is where
it will be read. Do not copy those explanations into this file; add a pointer instead.

| Question | Read |
|---|---|
| How do I check anything from inside the Claude Code sandbox? | the `no-daemon-check` skill, `scripts/no-daemon-check.sh` |
| How do I evaluate one expression from inside the sandbox, without running the whole suite? | `scripts/sandbox-eval.sh` (the header comment), `just eval` |
| Why does a green check here mean nothing if `<nixpkgs>` came from the flake registry? | `scripts/locked-nixpkgs.sh` (the header comment) |
| Where does a `fetchFromGitHub` hash come from with no network and no daemon? | `scripts/offline-src-hash.sh` (the header comment), `just hash-src` |
| When is a repository's `export-subst` actually fatal to an offline hash, and when is it not? | `scripts/offline-src-hash.sh` (the header comment, and the `export-subst` branch) |
| Why is `sisl` pinned to a tag rather than main, and what did the extra commits break? | `pkgs/sisl/default.nix` (the note above `src`) |
| Why is `node-graph` pinned to v0.6.5 exactly, one commit behind its main? | `pkgs/node-graph/default.nix` (the note above `src`) |
| Why does `sisl` patch `cmake.verbose` at the tag it is pinned to? | `pkgs/sisl/default.nix` (`postPatch`) |
| Why does one `aiida-workgraph` test gain a daemon fixture and another a longer timeout? | `pkgs/aiida-workgraph/default.nix` (the note above `postPatch`) |
| Why do two `aiida-workgraph` CLI tests fail at 32 xdist workers and pass at 128? | `pkgs/aiida-workgraph/default.nix` (the note above `patches`), `pkgs/aiida-workgraph/await-daemon-adoption.patch` |
| Why does `aiida-workgraph` raise `daemon.timeout` to 30, and why on the profile rather than globally? | `pkgs/aiida-workgraph/default.nix` (the last note above `postPatch`) |
| Why are `aiida-phonopy`'s two workflow tests deselected when the rest of its suite runs? | `pkgs/aiida-phonopy/default.nix` (`disabledTestPaths`) |
| Why is `aiida-phonopy`'s `phonopy~=4.0` relaxed, and what does 26.05's phonopy 3.5.1 still get wrong? | `pkgs/aiida-phonopy/default.nix` (`pythonRelaxDeps`) |
| Why is `ls` — or `git`, or `nix` — not on PATH inside the sandbox, and how do I get it back? | `scripts/sandbox-path.sh` (the header comment) |
| Why `python313` and not `python3`? What is `meta.broken` protecting? | `pkgs/qcportal/default.nix` (`meta`), `default.nix` |
| Why is Psi4 taken from a hand-pinned `nixpkgs-qchem`, and why not `nixos-qchem.packages.*`? | `flake.nix` (the `nixpkgs-qchem` input, and `qchemPkgs` in `perSystem`) |
| Why does `qchemPkgs` rewrite `python3` before the qchem overlay, and what does that cost? | `flake.nix` (`workerPython` and the first entry in `qchemPkgs`' `overlays`) |
| Why does the compute unit set `PYTHONPATH`, and why per-program envs? | `nixos-modules/qcfractal-compute.nix` |
| Why is a QC program built for another Python an eval error rather than one that is quietly skipped? | `nixos-modules/qcfractal-compute.nix` (the first entry in `assertions`) |
| Why three systemd units on the server, and why is `upgrade-db` manual by default? | `nixos-modules/qcfractal-server.nix` |
| Why no `nix-build-uncached`, and what breaks between CppNix and Lix? | `Justfile` (the note above `ci-build`) |
| Why does `ci.nix` filter on `meta.license.free` when nothing here is unfree any more? | `ci.nix` (the note above `isBuildable`) |
| Why is `repeated_keys` disabled? Why does the whitespace hook skip `*.patch`? | `statix.toml`, `flake.nix` |
| Why does `qcfractalcompute` carry a patch? Why is `parsl` built from the sdist? | the respective `pkgs/*/default.nix` |
| How does a worker get an account and a password? Why `qcfractal-manage`? | `docs/bootstrapping-worker-credentials.md` |
| Why does `verdi` come from a `withPackages` env instead of `lib.getExe cfg.package`? | `nixos-modules/aiida.nix` (`pythonEnv`) |
| Why does the AiiDA module ensure the *database* when the QCFractal one deliberately does not? | `nixos-modules/aiida.nix` (`services.postgresql`) |
| Why does `database.createLocally` default to whether the storage backend is PostgreSQL? | `nixos-modules/aiida.nix` (the `createLocally` default, and the `useSqlite` assertion) |
| Why is the `core.sqlite_dos` `--filepath` pinned rather than left to aiida-core's default, and why under `.aiida`? | `nixos-modules/aiida.nix` (`profileSetup`, and the `storage.filepath` option) |
| Why are the two storage backends' setup flags built from a joined list rather than one indented string? | `nixos-modules/aiida.nix` (`commonProfileOptions`) |
| Why does the sqlite VM test do the work of two PostgreSQL ones in a single boot? | `tests/aiida/vm.nix` (`daemon-sqlite`) |
| Why `Type = "forking"` for the daemon, and where does that pid file come from? | `nixos-modules/aiida.nix` (`systemd.services.aiida-daemon`) |
| Why is `core.zeromq` the default broker, and why is aiida-core taken from git? | `pkgs/aiida-core/default.nix` (the `src` comment) |
| Why is nixpkgs' `pymatgen` interpreter gate lifted, and why is it a `let` binding? | `overlays/default.nix` (the `pymatgen` binding in the `aiida` extension) |
| Why does `aiida-psi4` patch `setup.json`? What is `reentry` doing there? | `pkgs/aiida-psi4/default.nix` (`postPatch`) |
| Why does every AiiDA package set `HOME` in `preBuild` rather than `preCheck`? | `pkgs/aiida-core/default.nix` (`preBuild`) |
| Why is cclib a flake input, and what does that cost on the NUR path? | `pkgs/harmonwig/default.nix` (the `cclib` argument), `flake.nix` (`cclibPkgs`) |
| Why can `aiida-gaussian` not be built at all, and what would it take? | `pkgs/aiida-gaussian/default.nix` (the `cclib` argument), `flake.nix` (`cclibPkgs`) |
| Why does `dbstep` skip `dbstep.graph` in its import check? Why is `pptk` not a dependency? | `pkgs/dbstep/default.nix` (`pythonImportsCheck`) |
| Why is `pythonRelaxDeps = true` on aqme rather than a list? Why is `test_csearch.py` disabled? | `pkgs/aqme/default.nix` |
| Why does `ccreg` drop its own `lwreg` requirement and add three undeclared ones? | `pkgs/ccreg/default.nix` (`pythonRemoveDeps`) |
| Why do three packages rewrite a `default-version` in `postPatch`? | `pkgs/mda-xdrlib/default.nix` (`postPatch`) |
| Why does MDAnalysis run no tests, and why is that not `doCheck = false`? | `pkgs/mdanalysis/default.nix` (the note above `pythonImportsCheck`) |
| Why does the AiiDA eval suite need a second, broken-allowing package set? | `tests/aiida/default.nix` (`brokenPkgs`) |
| Why do eight packages come from a git tag rather than PyPI? | `pkgs/kiwipy/default.nix` (the `src` comment) |
| Why does `aiida-shell` rewrite its conftest's broker to `core.zeromq`? | `pkgs/aiida-shell/default.nix` (`postPatch`) |
| Why does `aiida-shell` need `which` when two of its three path rewrites are absolute? | `pkgs/aiida-shell/default.nix` (`nativeCheckInputs`) |
| Why does the `aiida-shell` VM test run two jobs, and why does one of them exist only to be boring? | `tests/aiida/vm.nix` (`plugin-shell`) |
| Why does that test put `which` and `xtb` on *both* `systemPackages` and `extraPackages`? | `tests/aiida/vm.nix` (the `environment.systemPackages` note in `plugin-shell`) |
| Why is `gpaw` deliberately *not* a check input of `aiida-ase`? | `pkgs/aiida-ase/default.nix` (`pythonImportsCheck`) |
| Why does `aiida-nwchem` take `ase`, `pymatgen`, `seekpath` and `spglib` as check inputs? | `pkgs/aiida-nwchem/default.nix` (`nativeCheckInputs`) |
| Why does `aiida-nwchem` ask for two MPI ranks when its tests run one water molecule? | `pkgs/aiida-nwchem/default.nix` (`postPatch`) |
| Why do `aiida-nwchem`'s tests lose their `system crystal` cell, and what did that cover? | `pkgs/aiida-nwchem/default.nix` (`postPatch`) |
| Why is `node-graph-widget-js` a top-level attribute rather than a Python one, and who consumes it? | `overlays/default.nix` (the `node-graph-widget-js` binding), `pkgs/node-graph-widget/default.nix` (`preBuild`) |
| Why does `node-graph-widget` copy a bundle in before hatchling runs, and what is `skip-if-exists`? | `pkgs/node-graph-widget/default.nix` (`preBuild`) |
| Why does `node-graph-widget-js` patch a name and version into `package.json`, and why on one line? | `pkgs/node-graph-widget-js/default.nix` (`postPatch`) |
| Why is `firecrest-streamer` built from a subdirectory of another project, and why is `asyncio` removed? | `pkgs/firecrest-streamer/default.nix` (`sourceRoot`, `pythonRemoveDeps`) |
| Why does `pyfirecrest` need `firecrest-streamer` when nothing advertises it? | `pkgs/pyfirecrest/default.nix` (`dependencies`) |
| Why is `graphene-file-upload` here at all, and why is its Flask half excluded? | `pkgs/graphene-file-upload/default.nix` (`disabledTestPaths`) |
| Why does `starlette-graphene3` rewrite its build backend? | `pkgs/starlette-graphene3/default.nix` (`postPatch`) |
| Why can `pythonRelaxDeps` not fix a `git+https` requirement, and what does instead? | `pkgs/aiida-restapi/default.nix` and `pkgs/aiida-wannier90-workflows/default.nix` (`postPatch`) |
| What is the risk in relaxing `aiida-restapi`'s `lark~=0.11` to 1.3? | `pkgs/aiida-restapi/default.nix` (`pythonRelaxDeps`) |
| Which two `aiida-restapi` endpoints are broken under starlette 1.x, and why is that not `meta.broken`? | `pkgs/aiida-restapi/default.nix` (`disabledTestPaths`) |
| Why do three plugins create an AiiDA config in `preBuild`, when `HOME` and `AIIDA_PATH` are already set? | `pkgs/aiida-pythonjob/default.nix` (`preBuild`) |
| Why does `aiida-optimize` patch the same two lines in two different files? | `pkgs/aiida-optimize/default.nix` (`postPatch`) |
| Why does `pyfirecrest` run its tests from `tests/`? | `pkgs/pyfirecrest/default.nix` (`preCheck`) |
| Why does `aiida-pythonjob` delete an `addopts` line rather than add IPython? | `pkgs/aiida-pythonjob/default.nix` (`postPatch`) |
| Why does `aiida-workgraph` rewrite its broker and put `verdi` on the check PATH? | `pkgs/aiida-workgraph/default.nix` (`postPatch`, `preCheck`) |
| Why is `aiida-firecrest` the one plugin here with `doCheck = false`? | `pkgs/aiida-firecrest/default.nix` (the note above `doCheck`) |
| Why does `aiida-siesta` have three different names, and which one is the attribute? | `pkgs/aiida-siesta/default.nix` (the `pname` note) |
| Why does `aiida-siesta` hand sisl back an `R` it just read, and what did the missing one cost? | `pkgs/aiida-siesta/default.nix` (the third and fourth notes above `postPatch`) |
| Why does `aiida-gromacs` patch a build-system requirement, when `pythonRelaxDeps` exists? | `pkgs/aiida-gromacs/default.nix` (`postPatch`) |
| Why does `aiida-gromacs` put `$out/bin` on the check PATH? | `pkgs/aiida-gromacs/default.nix` (`preCheck`) |
| Why do `aiida-gromacs`' three metadynamics tests force `-ntmpi 1`, and what would a parallel one need? | `pkgs/aiida-gromacs/default.nix` (`postPatch`), `.scratch/nixpkgs-plumed-mpi.patch` |
| Why is `aiida-lammps`' `jsonschema~=3.2` merely relaxed, four major versions on? | `pkgs/aiida-lammps/default.nix` (`pythonRelaxDeps`) |
| Why does `aiida-lammps` pass `--lammps-exec lmp`? | `pkgs/aiida-lammps/default.nix` (`pytestFlags`) |
| Why does `sisl` not fetch its one submodule? | `pkgs/sisl/default.nix` (`src`) |
| Why does `sisl` set `dontUseCmakeConfigure` while still listing `cmake`? | `pkgs/sisl/default.nix` (`nativeBuildInputs`) |
| Why is `aiida-optimize`'s license a two-entry list, and what is the GPLv3 mention about? | `pkgs/aiida-optimize/default.nix` (`meta.license`) |
| Why is `pycifrw` carried here when nixpkgs has one, and when should it be deleted? | `pkgs/pycifrw/default.nix` (the header), `overlays/default.nix` (the `pycifrw` binding) |
| Why are the two `mosquito` overrides guarded, and why does 26.05 not need them? | `overlays/default.nix` (the `hasMetadataCheck` binding in the `aiida` extension) |
| Why do the two cp2k-\*-tools packages rewrite their build backend? | `pkgs/cp2k-output-tools/default.nix` (`postPatch`) |
| Why does `mrcfile` patch eight `.dtype` assignments instead of pinning NumPy? | `pkgs/mrcfile/default.nix` (`postPatch`) |
| Why is `octopus` a defaulted argument to `postopus`, and why `enableMpi = false` *and* `netcdffortran`? | `pkgs/postopus/default.nix` (the `octopus` argument), `overlays/default.nix` (the `postopus` callPackage) |
| Why is nixpkgs' `rdkit` rebuilt just to add a `.dist-info`, and what is the cheaper option? | `overlays/default.nix` (the `rdkit` binding in the `cheminformatics` extension) |
| Why do aiida-core's SSH transport tests live in a VM test rather than its check phase? | `pkgs/aiida-core/default.nix` (`disabledTestPaths`), `tests/aiida/vm.nix` (`transports-ssh`) |
| Why does the isolation harness drop `disabledTestPaths` modules itself instead of passing `--ignore-glob`? | `tests/aiida/isolation.nix` (the `excluded` array) |
| Why does the SSH VM hand itself a `/bin/bash` instead of patching the suite like the build does? | `tests/aiida/vm.nix` (`systemd.tmpfiles.rules` in `transports-ssh`) |
| Why does the process checker exit 3, and why does the poller raise on it rather than keep polling? | `tests/aiida/vm.nix` (`checkProcess`, `awaitProcess`) |
| Why does a process that never leaves WAITING dump the daemon log, and where does that path come from? | `tests/aiida/vm.nix` (`daemonLog`, `dump_process_diagnostics` in `awaitProcess`) |
| Why does the daemon unit put `bash` and `procps` on its PATH, when NixOS already supplies coreutils? | `nixos-modules/aiida.nix` (`path` on `systemd.services.aiida-daemon`) |
| Why does `plumpy` catch one more exception than upstream, and what does RabbitMQ 4 have to do with it? | `pkgs/plumpy/default.nix` (`postPatch`) |
| Why does `Process.spec()` build into a local and move `__called` onto the spec, and why did a lock not do? | `pkgs/plumpy/default.nix` (the shared-state note above `postPatch`) |
| Why does aiida-core want `procps`, `rsync` and `vim` as check inputs? | `pkgs/aiida-core/default.nix` (`nativeCheckInputs`) |
| What does relaxing aiida-core's `click<8.3` cost, and why patch the library? | `pkgs/aiida-core/default.nix` (the comment above `postPatch`) |
| Why are thirteen `test_remote.py` size-on-disk tests deselected on this machine? | `pkgs/aiida-core/default.nix` (the ZFS note in `pytestFlags`) |
| Why do the pytest-xdist workers each need their own PostgreSQL role? | `pkgs/aiida-core/default.nix` (the `storage.py` hunk in `postPatch`) |
| Why does `PostgresCluster` pin its port to the xdist worker index, and why does `_close` still tolerate a postmaster that was never running? | `pkgs/aiida-core/default.nix` (the `_create`/`_close` note above `postPatch`) |
| Why is the pinned port base 21000 rather than 45000, and what did the old comment get wrong? | `pkgs/aiida-core/default.nix` (the ephemeral-range note above `postPatch`) |
| Why do two group tests have `aiida_profile_clean` injected when upstream never asks for it? | `pkgs/aiida-core/default.nix` (the group-table note above `postPatch`) |
| Why does `test_backup` need `aiida_profile_clean` when the test before it cleans already? | `pkgs/aiida-core/default.nix` (the `test_backup` note above `postPatch`) |
| Why does one parser test call `spec()` before rebinding `define`, when nothing reads it? | `pkgs/aiida-core/default.nix` (the `test_parser.py` note above `postPatch`) |
| Why does one repository test read its isolated stream inside the `with` block? | `pkgs/aiida-core/default.nix` (the `test_repository.py` note above `postPatch`) |
| Why is RabbitMQ deleted from the *deprecated* pytest fixture plugin, and which packages does that fix? | `pkgs/aiida-core/default.nix` (the last note above `postPatch`) |
| Why does `TestLaunchersDryRun` need its own working directory? | `pkgs/aiida-core/default.nix` (the `test_launch.py` note above `postPatch`) |
| Why does `aiida-pseudo` put its own `$out/bin` on PATH for the check phase? | `pkgs/aiida-pseudo/default.nix` (`preCheck`) |
| Why does `aiida-gaussian-datatypes` list `aiida-core` twice, once as a dependency and once as a check input? | `pkgs/aiida-gaussian-datatypes/default.nix` (`preCheck`) |
| Why does `aiida-octopus` need `procps` when the failure is a `KeyError`? | `pkgs/aiida-octopus/default.nix` (`nativeCheckInputs`) |
| Why are `test_gs_molecule`'s reference numbers rewritten rather than the test deselected? | `pkgs/aiida-octopus/default.nix` (`postPatch`) |
| Why does `aiida-testing` add one comma to `setup.cfg`, and why can `pythonRelaxDeps` not do it? | `pkgs/aiida-testing/default.nix` (`postPatch`) |
| Why is `fastentrypoints` a build-system input when `setup.py` only warns without it? | `pkgs/aiida-testing/default.nix` (`build-system`) |
| Why does `aiida-testing` rewrite `collections.Iterable`, and what still blocks `test_diff.py`? | `pkgs/aiida-testing/default.nix` (`postPatch`, `nativeCheckInputs`) |
| Why do the recorded `mock-*` fixture directories get renamed, and how do I get the new digests? | `pkgs/aiida-testing/default.nix` and `pkgs/aiida-psi4/default.nix` (the notes above `postPatch`) |
| Why does `example_01` overwrite two `provenance.version` strings, and why only those? | `pkgs/aiida-psi4/default.nix` (the example_01 note above `postPatch`) |
| Why does `aiida-psi4` stop setting `codeinfo.withmpi`? | `pkgs/aiida-psi4/default.nix` (the note above `postPatch`) |
| Why are the per-worker role, port and `_close` fixes applied to *two* fixture modules? | `pkgs/aiida-core/default.nix` (the deprecated-plugin note above `postPatch`) |
| Why does `aiida-cp2k` need `procps` when the failure is `assert 303 == 0`? | `pkgs/aiida-cp2k/default.nix` (`nativeCheckInputs`) |
| Why does `aiida-cp2k` need `glibcLocalesUtf8` when it creates no database of its own? | `pkgs/aiida-cp2k/default.nix` (`preCheck`) |
| Why do three `which` tests still fail with `which` installed? | `pkgs/aiida-quantumespresso/default.nix` (`postPatch`) |
| Why does `aiida-quantumespresso` use `--dist worksteal` rather than xdist's default? | `pkgs/aiida-quantumespresso/default.nix` (`pytestFlags`) |
| Why does `aiida-quantumespresso` need `which`, and why do the *negative* tests need it too? | `pkgs/aiida-quantumespresso/default.nix` (`nativeCheckInputs`) |
| Why does the `matdyn` regression reference gain three `pbc` keys? | `pkgs/aiida-quantumespresso/default.nix` (`postPatch`) |
| Why is aiida-core's `jq` threaded in from `final` instead of resolved through the Python set? | `overlays/default.nix` (the `aiida-core` callPackage) |
| Which aiida-core failures are retried rather than deselected, and what makes that sound? | `pkgs/aiida-core/default.nix` (the `--only-rerun` block in `pytestFlags`) |
| Why does aiida-core raise five of upstream's timeouts, and why is none of them an `--only-rerun` entry? | `pkgs/aiida-core/default.nix` (the wall-clock note at the end of `postPatch`) |
| Why is pytest-timeout's 240-second cap overridden to 900, and which test forces it? | `pkgs/aiida-core/default.nix` (the note above `--override-ini=timeout=900` in `pytestFlags`) |
| Why does `core.sqlite_dos` get WAL and a 60-second busy timeout, and what did the default cost? | `pkgs/aiida-core/default.nix` (the note above `patches`), `pkgs/aiida-core/sqlite-dos-concurrent-access.patch` |
| Why does that patch also touch `verdi storage backup`? | `pkgs/aiida-core/sqlite-dos-concurrent-access.patch` (the `_backup_storage` paragraph) |
| Why is one `database is locked` reported as two unrelated aiida-workgraph failures? | `pkgs/aiida-workgraph/default.nix` (the third note above `patches`), `pkgs/aiida-core/default.nix` (the note above `patches`) |
| Why does `cp2k-input-tools` declare no `lsp` extra, and drop one console script? | `pkgs/cp2k-input-tools/default.nix` (`postPatch`) |
| Why is `monty` patched rather than having its pandas tests skipped? | `overlays/default.nix` (the `monty` binding) |
| Why are nine `pymatgen` tests deselected by node id rather than by name? | `overlays/default.nix` (the `pymatgen` binding) |
| Why does `pgtest` need `enabledTestPaths` when its tests are right there? | `pkgs/pgtest/default.nix` (`enabledTestPaths`) |
| Why does `disk-objectstore` want `rsync` and `openssh` as check inputs? | `pkgs/disk-objectstore/default.nix` (`nativeCheckInputs`) |
| Why is `profilehooks` here at all, and why does it keep upstream's `addopts`? | `pkgs/profilehooks/default.nix` |
| Why does `pgsu` need `glibcLocalesUtf8` and a `LOCALE_ARCHIVE` export? | `pkgs/pgsu/default.nix` (`preCheck`) |
| Why is the pymatgen interpreter lift a shared `pymatgenFor` function, and why must it never join a package set? | `overlays/default.nix` (the `pymatgenFor` binding at the top) |
| Why does `pkgs.chemfiles` mean the C++ library while `python313Packages.chemfiles` means the binding? | `default.nix` (the `inherit (pkgs') chemfiles` note), `overlays/default.nix` (the `chemtools` callPackage) |
| Why does `chemfiles-python` refuse to fetch its own submodule, and what does `postInstall` assert? | `pkgs/chemfiles-python/default.nix` (`src`, `postInstall`) |
| Why does `chemfiles-python` run `unittest discover` instead of `pytestCheckHook`? | `pkgs/chemfiles-python/default.nix` (`checkPhase`) |
| How does the chemfiles C++ suite get its test data with no network, and why `ctest` rather than a check target? | `pkgs/chemfiles/default.nix` (the note above `preConfigure`, and `checkPhase`) |
| Why does `chemfiles-python` ask for chemfiles 0.11 when upstream's CMakeLists says 0.10? | `pkgs/chemfiles-python/default.nix` (`postPatch`) |
| Why is `pyrr` carried here at all, and when should it be deleted? | `pkgs/pyrr/default.nix` (the header) |
| What was pyrr's NumPy 2 incompatibility, actually? It is three defects, not one | `pkgs/pyrr/default.nix` (the note above `patches`), `pkgs/pyrr/numpy2.patch` |
| Why does `molara` relax PySide6 with `pythonRelaxDeps` when `sella` had to patch its pin instead? | `pkgs/molara/default.nix` (`pythonRelaxDeps`), `pkgs/sella/default.nix` (`postPatch`) |
| Why is the `trexio` Python binding built from a PyPI sdist rather than the git tag? | `pkgs/trexio/default.nix` (the `src` comment) |
| Why does `trexio` restore one test file from GitHub, and where did its sdist hash come from? | `pkgs/trexio/default.nix` (the `testSrc` note) |
| Why must the `trexio` binding never become a top-level attribute? | `overlays/default.nix` (the `trexio` binding in `chemtools`), `tests/chemtools/default.nix` (the trexio split) |
| Why does `xyzgraph` live in `cheminformatics` when `graphrc` and `xyzrender` need cclib? | `overlays/default.nix` (the `xyzgraph` binding) |
| Why is `graphrc` a top-level attribute *and* not re-exported? | `overlays/default.nix` (the `graphrc` binding), `tests/cheminformatics/default.nix` (`cclibDependencies`) |
| Why does `xyzrender` need neither `vmol` nor `shelxfile`, which nixpkgs lacks? | `pkgs/xyzrender/default.nix` (`nativeCheckInputs`) |
| Where do `metallogen`'s tests come from, when upstream ships none? | `pkgs/metallogen/tests/test_examples.py` (the module docstring), `pkgs/metallogen/default.nix` (the note above `preCheck`) |
| Why does `wignernj` delete its own source directory before the check phase? | `pkgs/wignernj/default.nix` (`preCheck`) |
| Why is `moltui` a top-level attribute rather than a `python313Packages` member? | `overlays/default.nix` (the `moltui` binding in `chemtools`), `tests/chemtools/default.nix` (`applicationPackages`) |
| Why does `sella` derive `SETUPTOOLS_SCM_PRETEND_VERSION` from `version` instead of repeating it? | `pkgs/sella/default.nix` (the `env` note) |
| Why does `custodian` take pymatgen as a *check* input, and why does that need the gate lifted? | `pkgs/custodian/default.nix` (`nativeCheckInputs`) |
| Why does `sella` delete its own source directory before the check phase? | `pkgs/sella/default.nix` (the note above `preCheck`), `pkgs/wignernj/default.nix` (the same trap, silent) |
| Why does `sella` set `HOME` when nothing in it writes to one? | `pkgs/sella/default.nix` (the note above `preBuild`) |
| How do `fireworks`' database tests run with no MongoDB, and why not just deselect them? | `pkgs/fireworks/default.nix` (the `MONGOMOCK_SERVERSTORE_FILE` note above `preCheck`) |
| Why is `maggma` the one package here where a `::` entry in `disabledTestPaths` silently does nothing? | `pkgs/maggma/default.nix` (the note above `disabledTests`) |
| Which of `maggma`'s test modules need a live MongoDB, and what coverage does dropping them cost? | `pkgs/maggma/default.nix` (`disabledTestPaths`) |
| Why does `mongomock-ng` export `NO_LOCAL_MONGO`, and how is it a third mongomock? | `pkgs/mongomock-ng/default.nix` (`preCheck`, and the note above `src`) |
| Why must `fireworks` never gain `pytest-xdist`, when nothing in the derivation asks for `-n`? | `pkgs/fireworks/default.nix` (the note above `nativeCheckInputs`) |
| Why are two `WFLockTest` tests deselected when they only ever skip themselves? | `pkgs/fireworks/default.nix` (`disabledTestPaths`) |
| Why does `fireworks` pass `-rs`, and which six tests still skip? | `pkgs/fireworks/default.nix` (`pytestFlags`) |
| Why is `mongomock-persistence` carried here, and why is it not a top-level attribute? | `pkgs/mongomock-persistence/default.nix` (the `src` comment), `tests/chemtools/default.nix` (`internalDependencies`) |
| Why does `fireworks` need `igraph`, `graphviz` and `matplotlib` to test, and why is `mainProgram` `lpad`? | `pkgs/fireworks/default.nix` (`nativeCheckInputs`, `meta.mainProgram`) |
| Why does `metallogen` set `doCheck = false` when `MetalloGen/test.py` exists? | `pkgs/metallogen/default.nix` (the `doCheck` note) |
| Why does the chemtools python-pin test compose *every* overlay when the cheminformatics one does not? | `tests/chemtools/default.nix` (the `fullyOverlaidPkgs` binding) |
| Why does this repo carry a `monty` at all, and when should it go? | `pkgs/monty/default.nix` (the header), `overlays/default.nix` (the `monty` binding in the materials overlay) |
| Why does `monty` need a bson fix its own test suite cannot see? | `pkgs/monty/default.nix` (`postPatch`), `overlays/default.nix` (the aiida overlay's `monty` binding) |
| Why does `pymatgen-core` *replace* nixpkgs' `pymatgen` rather than sit beside it? | `pkgs/pymatgen-core/default.nix` (the header) |
| How do two distributions share the `pymatgen/` tree without colliding in a `withPackages`? | `pkgs/pymatgen-core/default.nix` (the header) |
| Why does `pymatgen-core` delete its own `pmg` console script? | `pkgs/pymatgen-core/default.nix` (`postPatch`) |
| Why is `pymatgen` pinned to a commit when it has a tag, and why is the submodule left empty? | `pkgs/pymatgen/default.nix` (the `src` note) |
| Why does the pure-Python half of pymatgen still need Cython to build? | `pkgs/pymatgen/default.nix` (`build-system`) |
| Why does `pymatgen` feed setuptools-scm only the part of `version` before the dash? | `pkgs/pymatgen/default.nix` (the `env` note) |
| Why do both pymatgen halves export `PMG_TEST_FILES_DIR`, and why a different directory each? | `pkgs/pymatgen-core/default.nix` and `pkgs/pymatgen/default.nix` (`preCheck`) |
| Why is `pymatgenFor` keyed on a version now, and what aborts without the guard? | `overlays/default.nix` (`pymatgenFor`) |
| Why does `tests/aiida`'s python-pin test compose every overlay too, when it did not have to before? | `tests/aiida/default.nix` (the `fullyOverlaidBrokenPkgs` binding) |
| Why does `enumlib` fetch `symlib` a second time rather than as a submodule? | `pkgs/enumlib/default.nix` (the `symlib` binding) |
| Why does `enumlib` bake a `git describe` string into a Makefile, and what reads it? | `pkgs/enumlib/default.nix` (`postPatch`) |
| Why is `enumlib` built serially, and why is `2Dplot.x` left out? | `pkgs/enumlib/default.nix` (`buildPhase`) |
| Where does `enumlib`'s check get an expected answer, when upstream runs no tests? | `pkgs/enumlib/default.nix` (`checkPhase`) |
| Why must `enumlib` be on atomate2's *PATH* rather than merely installed? | `pkgs/atomate2/default.nix` (`nativeCheckInputs`) |
| Why does `vise` delete two `distutils` imports rather than add setuptools at runtime? | `pkgs/vise/default.nix` (`postPatch`) |
| Why does `vise` declare nine dependencies its own requirements.txt does not? | `pkgs/vise/default.nix` (`dependencies`) |
| Why is `vise` pinned 827 commits past its tag, and are its POTCARs a licensing problem? | `pkgs/vise/default.nix` (the `src` note, `enabledTestPaths`) |
| Why is `boltztrap2` a `vise` dependency rather than a check input? | `pkgs/vise/default.nix` (the note above `dependencies`) |
| Where does `vise` get a POTCAR directory from, with no VASP licence? | `pkgs/vise/default.nix` (`preCheck`) |
| Why is `tensorpotential` not a top-level attribute when every other tool here is? | `overlays/default.nix` (the `tensorpotential` binding), `ci.nix` (the note above `isBuildable`) |
| Why does `tensorpotential` spell `redistributable` out instead of letting it default? | `pkgs/tensorpotential/default.nix` (`meta.license`) |
| Why does dropping `tensorflow[and-cuda]` not cost GPU support? | `pkgs/tensorpotential/default.nix` (`postPatch`) |
| Why can `matcalc` take an unfree extra and stay free and cacheable? | `pkgs/matcalc/default.nix` (the note above `optional-dependencies`) |
| Why does `matplotlib-label-lines` need `pytest-mpl` when the image comparison is switched off? | `pkgs/matplotlib-label-lines/default.nix` (`nativeCheckInputs`) |
| Why must `labellines/test.py` be named in `enabledTestPaths` rather than found? | `pkgs/matplotlib-label-lines/default.nix` (`enabledTestPaths`), `pkgs/pgtest/default.nix` |
| Why does `hiphive` run only `tests/unittests` when `tests/integration` looks like tests too? | `pkgs/hiphive/default.nix` (`enabledTestPaths`) |
| Why does `cmcrameri` need `SETUPTOOLS_SCM_PRETEND_VERSION` when nothing errors without it? | `pkgs/cmcrameri/default.nix` (the `env` note) |
| How is the `doped` ↔ `shakenbreak` cycle cut, and why is that permanent rather than a bootstrap? | `pkgs/doped/default.nix` (the note above `pythonRemoveDeps`) |
| Why can `doped`'s suite run with no VASP when `vise`'s cannot? | `pkgs/doped/default.nix` (`enabledTestPaths`), `pkgs/vise/default.nix` (`disabledTestPaths`) |
| Why must neither `doped` nor `shakenbreak` ever gain `pytest-xdist`? | `pkgs/doped/default.nix` and `pkgs/shakenbreak/default.nix` (`nativeCheckInputs`), `pkgs/fireworks/default.nix` |
| Why is one `doped` test deselected by node id when the other 39 go by name? | `pkgs/doped/default.nix` (`pytestFlags`) |
| Why does `shakenbreak` declare `hiphive` when nothing imports it at module scope? | `pkgs/shakenbreak/default.nix` (the note above `dependencies`) |
| Why does `deepmd-kit` turn *both* its backends off, and what does that give up? | `pkgs/deepmd-kit/default.nix` (the note above `env`) |
| Why do `torch` and `ase` become `deepmd-kit` dependencies when upstream declares neither? | `pkgs/deepmd-kit/default.nix` (the note above `dependencies`) |
| Why is `deepmd-kit` the one package here whose `doCheck = false` is about the backends being off? | `pkgs/deepmd-kit/default.nix` (the note above `doCheck`) |
| How does `fairchem-core` run a suite that lives outside the `sourceRoot` its wheel is built from? | `pkgs/fairchem-core/default.nix` (`preCheck`) |
| Why do upstream's pytest `addopts` not apply to `fairchem-core`, and why is that welcome? | `pkgs/fairchem-core/default.nix` (the note above `preCheck`) |
| Why is `dargs`' licence `lgpl3Only` when its one dependant says `or-later`? | `pkgs/dargs/default.nix` (`meta.license`) |
| Why does `dargs` pin a setuptools-scm version it would probably get right anyway? | `pkgs/dargs/default.nix` (the note above `env`) |
| Why is `dargs.sphinx` left out of the import check? | `pkgs/dargs/default.nix` (`pythonImportsCheck`), `pkgs/dbstep/default.nix` (the same shape) |
| Why is `dpdata`'s `lmdb>=2.0.0` relaxed when that repo *pinned* py-lmdb down for a reason? | `pkgs/dpdata/default.nix` (`pythonRelaxDeps`), `overlays/default.nix` (the `lmdb` binding) |
| Why does `dpdata` delete its own source directory *and* run from `tests/`? | `pkgs/dpdata/default.nix` (`preCheck`), `pkgs/sella/default.nix` and `pkgs/wignernj/default.nix` (the same trap, less explicit) |
| Why does `dpdata` empty pytest's `python_classes`, and what breaks without it? | `pkgs/dpdata/default.nix` (`pytestFlags`) |
| Why does `dpdata` load a plugin with `-p` instead of packaging `tests/plugin`? | `pkgs/dpdata/default.nix` (`pytestFlags`) |
| Which `dpdata` tests are deselected, and which of them is an upstream `try:` block with no import in it? | `pkgs/dpdata/default.nix` (`disabledTests`) |
| Why does `dpdata-plugin-test` have to be installed rather than imported, and how is the cycle cut? | `pkgs/dpdata-plugin-test/default.nix` (the header, and `dependencies`) |
| Why can `scripts/offline-src-hash.sh` not answer for `parmed`, and where did its hash come from? | `pkgs/parmed/default.nix` (the `src` note) |
| Why does `parmed` need no pretend version when it uses versioneer and has no `.git`? | `pkgs/parmed/default.nix` (the `src` note) |
| Which two `parmed` test modules are dropped, and which of them could come back through NixOS-QChem? | `pkgs/parmed/default.nix` (`disabledTestPaths`) |
| How do I build `parmed` against AmberTools, and why is it not a check? | `flake.nix` (`parmedWithAmbertools`), `pkgs/parmed/default.nix` (the `ambertools` argument) |
| Why does `parmed` set `GMXDATA`, and what did 93 skips turn out to be? | `pkgs/parmed/default.nix` (`nativeCheckInputs`, `preCheck`) |
| Why does `parmed` pass `-rsfE` rather than `-rs`? | `pkgs/parmed/default.nix` (`pytestFlags`) |
| Why does `basis-set-exchange` run its tests from `$out` rather than the unpacked source? | `pkgs/basis-set-exchange/default.nix` (`preCheck`) |
| Why is `basis-set-exchange`'s `--runslow` left off, and what does turning it on cost? | `pkgs/basis-set-exchange/default.nix` (`nativeCheckInputs`), `docs/TODO.md` |
| Why is `wignernj` a defaulted argument to `basis-set-exchange` when this repo has it? | `pkgs/basis-set-exchange/default.nix` (the `wignernj` argument), `overlays/default.nix` (the `basis-set-exchange` callPackage) |
| Why is `openbabel-bindings` a `dpdata` check input when every openbabel import in it is function-local? | `pkgs/dpdata/default.nix` (the note above `nativeCheckInputs`) |
| How does one distribution get built out of the thirteen-package `fairchem` monorepo? | `pkgs/fairchem-core/default.nix` (`sourceRoot`), `pkgs/emmet-core/default.nix` (the same arrangement) |
| Which of `fairchem-core`'s four relaxed pins is the one worth worrying about? | `pkgs/fairchem-core/default.nix` (the note above `pythonRelaxDeps`) |
| Why does `torchtnt` get patched here, and what does setuptools 83 have to do with it? | `overlays/default.nix` (the `torchtnt` binding in the materials overlay) |
| Why is `py-lmdb` pinned *down* to 1.7.3, and which three relaxations did that remove? | `overlays/default.nix` (the `lmdb` binding in the materials overlay) |
| Why is `fairchem.core...recipes.omol` kept out of the import check, now that `fairchem-data-omol` exists? | `pkgs/fairchem-core/default.nix` (`pythonImportsCheck`) |
| Why is `test_omol_recipes.py` still deselected after the distribution it wanted was packaged? | `pkgs/fairchem-core/default.nix` (the first entry in `disabledTestPaths`) |
| How do four distributions out of one monorepo share the `fairchem/` import path? | `pkgs/fairchem-data-omol/default.nix` (the header) |
| Why does `fairchem-data-omol` not declare the `quacc` its own module imports? | `pkgs/fairchem-data-omol/default.nix` (`optional-dependencies`), `pkgs/quacc/default.nix` (the `fairchem` extra) |
| Why is `fairchem-data-oc` pinned past its tag when the other two data packages are not? | `pkgs/fairchem-data-oc/default.nix` (the `src` note) |
| Where does `fairchem-data-oc`'s 36 MB bulk database come from, when upstream downloads it on first use? | `pkgs/fairchem-data-oc/default.nix` (the `bulksPkl` note) |
| Why is `fairchem-data-oc` the one package here whose licence is a list for a *data* reason? | `pkgs/fairchem-data-oc/default.nix` (`meta.license`) |
| Why must `fairchem-data-oc` never gain `pytest-xdist`? | `pkgs/fairchem-data-oc/default.nix` (`preCheck`), `pkgs/fireworks/default.nix` |
| Why is `packmol` a defaulted argument, and why is it null where `postopus`' `octopus` is not? | `pkgs/fairchem-data-oc/default.nix` (the `packmol` argument), `overlays/default.nix` (the `fairchem-data-oc` callPackage), `pkgs/postopus/default.nix` |
| Why does `fairchem-data-oc` take `fairchem-core` when upstream declares no such dependency? | `pkgs/fairchem-data-oc/default.nix` (`dependencies`) |
| Why does `fairchem-data-omat` need no POTCAR directory when `vise` loses 23 tests to one? | `pkgs/fairchem-data-omat/default.nix` (the note above `pythonImportsCheck`) |
| Why do the two fairchem data packages delete `tests/conftest.py` before running their own suites? | `pkgs/fairchem-data-omat/default.nix` (`preCheck`), `pkgs/fairchem-data-oc/default.nix` (the same note, from the other side) |
| Why is `clusterscope` pinned to v0.0.18 rather than its own latest release? | `pkgs/clusterscope/default.nix` (the note above `src`) |
| Why does `ase-db-backends` drop `psycopg2-binary` for `psycopg2`? | `pkgs/ase-db-backends/default.nix` (`pythonRemoveDeps`) |
| Where do `ase-db-backends`' PostgreSQL and MySQL tests actually run, if not in its build? | `tests/materials/vm.nix` |
| Why does `ase-db-backends` list `ase` as both a dependency and a check input? | `pkgs/ase-db-backends/default.nix` (`nativeCheckInputs`) |
| Which `ase-db-backends` tests skip themselves, and which actually run? | `pkgs/ase-db-backends/default.nix` (`enabledTestPaths`) |
| Why does `ase-db-backends` patch `close()`, and what did reopening-to-close break? | `pkgs/ase-db-backends/close-must-not-reopen.patch`, `docs/TODO.md` |

### The sdist-has-no-tests trap

Eight packages here take `src` from `fetchFromGitHub` purely because their sdist ships no test
directory — flit's `[tool.flit.sdist] exclude` naming `tests/` is the usual cause, and poetry
projects that publish wheels only are the other. The failure is normally **silent**:
`pytestCheckPhase` collects zero items and the build goes green, so a package can sit for months
looking tested when nothing ran. It turns loud only by accident — `pgtest` exited 5 on an empty
collection, and `kiwipy` aborted because a `disabledTestPaths` glob matched nothing.

When adding a `buildPythonPackage` here, check that the suite actually ran before believing it.
`disabledTestPaths` is a useful canary precisely because a glob matching nothing is fatal. So is
`enabledTestPaths`, which the hook expands as a glob and aborts on — `pgtest` needs it, because
its one test module is named `test.py` and pytest's default `python_files` matches neither
`test_*.py` nor `*_test.py` against that.

**Expect the fix to reveal the next layer, not to finish the job.** Every package whose suite was
recovered this way then failed on something the missing tests had been hiding, and each of those
failures hid the one behind it: `mrcfile` building unblocked `mdanalysis`, which unblocked
`qmzyme`, which then failed on its own `versioningit~=2.0` build pin. Budget for several rounds,
and run the build with `--keep-going` so one round reports every leaf rather than the first.


### Tests that need a live server belong in a VM test

A check phase cannot run PostgreSQL, MySQL or MongoDB, so a suite that wants one can only
**skip** — and a skipped test is indistinguishable from a passing one in a build log. Do not
leave it there. Put the package's check phase on what it can genuinely verify, and move the
server-backed tests to a `tests/<suite>/vm.nix` entry that boots the real service.

`pkgs/ase-db-backends` is the worked example: 27 of its 28 tests skip during the build for want
of a PostgreSQL and a MySQL, which made a green build nearly meaningless.
`tests/materials/vm.nix` runs those against real servers, and asserts that nothing *skipped* —
because a skip there would mean the connection URL never reached the suite, which is the exact
failure the build could not distinguish.

The same reasoning already governs `pkgs/fireworks` and `pkgs/maggma`, which reach for MongoDB;
those are handled differently (mongomock, and dropping the modules) and are the standing
counter-examples to weigh a new case against.


## Architecture

### Two entry points, one source of truth

`default.nix` is the NUR entry point and the canonical package list. `flake.nix` and
`overlay.nix` both derive from it:

- `flake.nix` → `legacyPackages` = `import ./default.nix`, plus `parmed-ambertools`; `packages` =
  the derivations filtered out of that, plus the seven cclib ones.
- `overlay.nix` → the same attrset minus the *reserved* keys.

Both additions are there because a flake input cannot be reached from `default.nix`, and the two
sit in different outputs for a reason worth knowing: `nix flake check` forces `packages` but not
`legacyPackages`. The cclib seven can live in `packages` because their sources are ordinary
fetches; `parmed-ambertools` cannot, because NixOS-QChem builds AmberTools from a `requireFile`
tarball the user has to fetch by hand, and a `packages` or `checks` entry would fail every build
that has not. See `flake.nix` (`parmedWithAmbertools`).

`flake.nix` is a **flake-parts** flake: `systems` comes from `nix-systems/default`, per-system
outputs live in `perSystem`, and `nixosModules` / `overlays` sit in the system-agnostic `flake`
block. `perSystem`'s `pkgs` argument is the *un-overlaid* nixpkgs — `default.nix` applies the
overlays itself, so `legacyPackages` must use it as-is. The separate `pkgs'` in the `let` is the
overlaid set, and is what the eval and VM tests need.

**Reserved keys** (`lib`, `overlays`, `nixosModules`, `homeModules`, `darwinModules`,
`flakeModules`, `python313Packages`) are attrs in `default.nix` that must not be lifted into a
nixpkgs overlay. The `isReserved` predicate is duplicated in both `overlay.nix` and `ci.nix` —
adding a new reserved key means editing both.

`python313Packages` is the one that is ours rather than the NUR template's, and the one where
getting it wrong does real damage: it is the whole overlaid 3.13 set, exposed so that the
twenty-odd dependencies this repo carries but does not re-export have an attribute path —
`nix-update --flake python313Packages.mdanalysis`. Leaking it into the overlay would replace a
consumer's `python313Packages` with the one `default.nix` builds from its own `pkgs'`. It also
carries `dontRecurseIntoAttrs`, which is what keeps `nix-env -f . -qa '*'` and `ci.nix`'s
`flattenPkgs` from descending into ten thousand nixpkgs packages; both honour
`recurseForDerivations`, and neither would otherwise stop.

### Adding a Python package takes three edits

The `qcfractal`, `aiida` and `cheminformatics` overlays in `overlays/default.nix` each inject
their Python packages into `pythonPackagesExtensions`, so they land in *every* `pythonX.pkgs`
set, **and** re-export the public ones as top-level `pkgs.*` aliases. `default.nix` then
re-exports the same names from `pkgs'.python313Packages`. All three routes are the *same*
derivation, which the `overlay-python-pin` and `aiida-overlay-python-pin` eval tests assert. So a
new package needs:

1. the `pself.callPackage` line in `overlays/default.nix`,
2. the top-level `inherit (final.python313Packages)` list in the same file,
3. the `inherit (py)` list in `default.nix`.

Steps 2 and 3 are for *public* packages only. The AiiDA and cheminformatics overlays between them
carry twenty-odd dependencies — `kiwipy`, `plumpy`, `disk-objectstore`, `pgsu`, `aiida-pseudo`,
`mdanalysis`, `colour-science`, `lwreg` and the rest — that stop at step 1 deliberately: they stay
reachable through `python313Packages` and are not top-level attributes, so `ci.nix` does not build
each of them in its own right. `tests/aiida/default.nix` spells out the public AiiDA list in
`exportedPackages`, a fourth hand-written copy that exists so the other three cannot drift apart
silently.

**A cclib dependant is the exception to all of this.** It is a top-level
`final.python3.pkgs.callPackage` in `overlays/default.nix` — one edit, not three — plus a line
in `default.nix`'s `inherit (pkgs')` list and one in `flake.nix`'s `packages` override. It is not a
`pythonPackagesExtensions` member because `python313Packages` is precisely the set that never has
cclib. `aiida-gaussian` breaks that rule and pays for it by being unbuildable; see the cclib split
above.

Inside a package derivation, dependencies on sibling packages resolve automatically through the
extended package-set fixpoint (`pself`) — do not thread them in manually. Non-Python packages
are plain `pkgs'.callPackage` calls in `default.nix`.

The top-level aliases are load-bearing, not a convenience: all three NixOS modules use
`lib.mkPackageOption pkgs "qcfractal"` / `"qcfractalcompute"` / `"aiida-core"`, which resolves
against the top level of `pkgs`. Dropping them makes every consumer of the overlay fail with
"qcfractal cannot be found in pkgs".

Packages driven by the modules also need `meta.mainProgram`: the modules launch them with
`lib.getExe`, which silently falls back to the *package* name, and none of the console scripts
is named after its package (`qcfractal` → `qcfractal-server`, `qcfractalcompute` →
`qcfractal-compute-manager`, `aiida-core` → `verdi`).

### What CI builds

`ci.nix` flattens `default.nix` and filters by `meta.broken`, `meta.license.free` and
`preferLocalBuild`. **A package that cannot build must carry `meta.broken = true;`** or CI and
cache population fail. `meta.broken` does not propagate to dependents and throws at *evaluation*
time, so each package that pulls in qcportal carries its own marking.

## Commands

**The `Justfile` is the source of truth for what CI runs.** `.github/workflows/build.yml` calls
the `ci-*` recipes rather than spelling the commands out, so `just ci <channel>` reproduces one
matrix leg end-to-end locally. Add CI logic there, not to the workflow.

```sh
just                      # list every recipe
just ci nixos-26.05       # one channel's full sequence; `just ci-matrix` for all three
just push nixos-26.05     # the same leg, uploaded to nur-berquist.cachix.org
just push-matrix          # all three legs, one upload session
just build qcfractal      # single package, NUR style; or nix build .#qcfractal
just check                # everything: both eval suites, every VM test, pre-commit hooks
just tests                # every non-VM suite reachable without the flake (see tests/AGENTS.md)
just harmonwig-tests      # the one suite that needs the flake, because cclib is an input
just vm-test server-local-db          # one VM test; needs KVM
just vm-test aiida-daemon-local-db    # the AiiDA VM tests are prefixed "aiida-"
just fmt / just lint / just hooks     # nixfmt, statix+deadnix, prek
just check-no-daemon                  # the eval-only subset; no nix-daemon needed
just eval vise.version                # one expression, likewise; see the skill
```

Tooling comes from the devShell (`nix develop`, or direnv). Entering it also generates
`.pre-commit-config.yaml` from the `pre-commit.settings.hooks` block in `flake.nix` — that block
is the source of truth and the generated file is gitignored.

Note that `nixConfig.extra-substituters` is ignored unless the invoking user is in
`trusted-users`. Without that, `nix flake check` silently builds Psi4 from source no matter how
correct the pinning is — check for `warning: ignoring untrusted flake configuration setting`
before blaming the derivation hashes.

## Deferred packaging

`wc/` holds upstream clones of the projects packaged here, and of several that are not yet.
This section records why the remainder are not, so the survey does not have to be redone. All
availability claims were probed against the locked nixpkgs with
`nix-instantiate --eval --store dummy://` over `python313Packages`, `python3.pkgs` and the top
level.

**The materials-project chain.** `atomate2`, `matcalc` and `quacc` are all packaged — the chain
is complete. Reading those targets' own `pyproject.toml` against the locked nixpkgs, this is
where the survey stands:

| Missing | Wanted by | Status |
|---|---|---|
| `maggma` | `jobflow` — its only gap | **done** |
| `qtoolkit` | `jobflow-remote` — its only gap | **done**; `dependencies = []`, which is why it went first |
| `mongomock-ng` | `maggma` | **done**; *not* the `mongomock` nixpkgs already has |
| `pubchempy` | `emmet-core` | **done** |
| `monty` | `pymatgen-core` | **done**; a backport, guarded — see `pkgs/monty/default.nix` |
| `pymatgen-core` | everything left | **done**; the split below |
| `pymatgen` | `emmet-core`, `atomate2` | **done**; the other half of the same split |
| `pymatgen-io-validation` | `emmet-core` | **done**; `pkgs/pymatgen-io-validation`, re-exported like `pubchempy` for the same reason |
| `mp-pyrho` | `pymatgen-analysis-defects` | **done**; `pkgs/mp-pyrho`, internal (dist `mp-pyrho`, import `pyrho`) |
| `pymatgen-analysis-alloys` | `emmet-core` tests, atomate2 `alloys` | **done**; `pkgs/pymatgen-analysis-alloys` |
| `pymatgen-analysis-defects` | `emmet-core` tests, atomate2 `defects` | **done**; `pkgs/pymatgen-analysis-defects` |
| `pymatgen-analysis-diffusion` | `emmet-core` tests, atomate2 `approxneb` | **done**; `pkgs/pymatgen-analysis-diffusion` — patches a `StructureGraph` rename upstream master has not caught |
| `optimade` | `emmet-core` tests | **done**; `pkgs/optimade` — the models half only, no FastAPI server |
| `lobsterpy` | `emmet-core` tests, atomate2 `lobster` | **done**; `pkgs/lobsterpy` at the v0.6.1 tag — the transitional release with both `lobsterpy.cohp` (atomate2) and `lobsterpy.coxx` (emmet-core); master deletes `cohp` |
| `mendeleev` | `lobsterpy[featurizer]` | **done**; `pkgs/mendeleev`, internal — element data from a bundled SQLite db |
| `matgl` | `emmet-core` tests, atomate2 forcefields | **done**; `pkgs/matgl` — `doCheck = false`, its suite needs Hugging Face model weights |
| `emmet-core` | `atomate2`, `quacc` | **done**; `pkgs/emmet-core`, one package out of the `materialsproject/emmet` monorepo — see below |
| `atomate2` | the chain's target | **done**; `pkgs/atomate2`. Core `dependencies` all satisfied. Extras done: `ase`, `ase-ext`, `mp`, `lobster`, `phonons`, `defects`, `approxneb`; still out: `forcefields`, `openff`, `torchsim`, `abinit`, `aims`, `amset`. `tests/{vasp,ase,lobster}` run in full, `test_magnetic_orderings` included since `enumlib` landed |
| `matcalc` | atomate2 follow-on | **done**; `pkgs/matcalc` — `doCheck = false`, its conftest imports `matgl` and every test downloads a model. Extras done: `phonon`, `phonon3` (phonopy-4 channels only), `benchmark`, `grace` (unfree — see `tensorpotential` below), `maml`, `matgl`, `mace` (unstable only), `sevennet`, `deepmd`, `fairchem`. Missing: none but `orb`/`mattersim`/`petmad`, which are NVIDIA-blocked (see below) |
| `tensorpotential` | `matcalc[grace]` | **done**; `pkgs/tensorpotential` (repo `ICAMS/grace-tensorpotential`) — **the one unfree package here.** Academic Software Licence: GPLv2 with a non-commercial clause, "not an open-source licence" by its own preamble. Reachable as `python313Packages.tensorpotential` only, deliberately not a top-level attribute — see `ci.nix` and the overlay binding |
| `mp-api` | `maml`, atomate2 `mp` | **done**; `pkgs/mp-api` — `doCheck = false` (every test drives a live MPRester). Dist `mp-api`, import `mp_api` |
| `maml` | `matcalc[maml]` | **done**; `pkgs/maml`, internal — `doCheck = false` (TensorFlow / matgl-model tests, `apps/pes` needs external fitting binaries) |
| `deepmd-kit` | `matcalc[deepmd]` | **done**; `pkgs/deepmd-kit`, internal — and it was on the *blocked* list for no better reason than never having been surveyed. Core dependencies are ordinary; `dargs` was the only gap. Built with `DP_ENABLE_TENSORFLOW=0` and `DP_ENABLE_PYTORCH=0`, which skips the CMake-against-libtorch op library — optional, see the derivation. `doCheck = false` |
| `dargs` | `deepmd-kit` — its only *core* gap | **done**; `pkgs/dargs`, internal. A real tagged release, unlike the rest of this cluster |
| `dpdata` | `deepmd-kit[dpa-adapt]`, `deepmd-kit[test]` | **done**; `pkgs/dpdata`, internal — the format converter, and what makes the `dpa-adapt` extra reachable. Its `lmdb>=2.0.0` is **relaxed against this repo's py-lmdb 1.7.3 pin**, the one place those two collide, and that costs three tests rather than nothing. The suite is upstream's `python -m unittest` one and needs `python_classes` emptied to run under pytest at all; `tests/context.py` is the `sys.path` shadowing trap in its most explicit form, and it also dictates the working directory |
| `parmed` | `dpdata[amber]`, `dpdata`'s suite | **done**; `pkgs/parmed`, internal — Amber/CHARMM/GROMACS topology editing, absent from nixpkgs, packaged so `dpdata`'s `TestPickByAmberMask` runs instead of erroring. One C++ extension, versioneer, and a `.gitattributes` export-subst that `scripts/offline-src-hash.sh` refuses to answer for — the hash was checked against the real codeload tarball |
| `dpdata-plugin-test` | `dpdata`'s suite | **done**; `pkgs/dpdata-plugin-test`, internal — the entry-point fixture out of dpdata's own `tests/plugin/`, built from the same `src` one directory down. It has to be *installed*, not imported, and its dpdata is a `doCheck = false` override to cut the cycle; see its header for both |
| `fairchem-core` | `matcalc[fairchem]`, `quacc[mlip]` | **done**; `pkgs/fairchem-core`, internal — one distribution out of a thirteen-package monorepo, built from `packages/fairchem-core/` whose `src` is a symlink to `../../src`. Also recorded as blocked without its dependencies having been read: only two were missing. `tests/core` runs, less nine modules needing Hugging Face checkpoints or the NVIDIA stack |
| `clusterscope` | `fairchem-core` | **done**; `pkgs/clusterscope`, internal — pinned to v0.0.18, the exact version fairchem-core's `==` names, rather than to its own latest |
| `ase-db-backends` | `fairchem-core` | **done**; `pkgs/ase-db-backends`, internal. GitLab, like `hiphive` and `trainstation`; no tags at all, so `-unstable-`. Dist and import are `ase_db_backends`. Carries a real upstream bugfix — `close()` reopened the LMDB environment in order to close it |
| `fairchem-data-omol` | `quacc[fairchem]` | **done**; `pkgs/fairchem-data-omol`, internal — ORCA input generation for OMol25. No tests exist upstream for this distribution, hence `doCheck = false`. Three undeclared module-scope imports added; `quacc` and `psutil`, which `orca/recipes.py` also imports, are deliberately *not* added — that is the other half of the `quacc[fairchem]` cycle |
| `fairchem-data-omat` | `quacc[fairchem]` | **done**; `pkgs/fairchem-data-omat`, internal — OMat24's VASP input set and MP-style corrections. `pymatgen` is its whole dependency list and for once that is also its whole import list. `tests/data/omat` runs; no POTCARs needed |
| `fairchem-data-oc` | `quacc[fairchem]` | **done**; `pkgs/fairchem-data-oc`, internal — OC20 adsorbate/slab generation. The awkward one of the three: pinned past its 2025-08 tag for a year of numpy/pymatgen catch-up, it takes `fairchem-core` (undeclared, module-scope, unguarded), and the 36 MB bulk database it is built around is a `fetchurl` installed into the wheel because upstream downloads it on first use. Six of its seven test modules would be dead without that; 30 of 34 tests pass, two xfail on a known pymatgen slab bug, and the last two want `packmol`, which **nixpkgs does not carry** — see the `octopus`-shaped defaulted argument |
| `quacc` | atomate2 follow-on | **done**; `pkgs/quacc`. Core `dependencies` all satisfied. Extras done: `dask`, `defects`, `fairchem`, `jobflow`, `mp`, `mlip`, `parsl`, `phonons`, `prefect`, `ray`, `redun`, `sella`, `tblite`. Missing: `torchsim` alone, and that is NVIDIA-blocked rather than unpackaged. Test round: ASE-native recipes + `wflow` |
| `shakenbreak` | `quacc[defects]` — the chain's last target | **done**; `pkgs/shakenbreak`, and with it the whole `defects` cluster: `doped`, `pydefect`, `vise`, `hiphive`, `trainstation`, `cmcrameri`, `matplotlib-label-lines`. It is the half of the `doped` cycle that declares the other; see `pkgs/doped` for why the cut goes that way |
| `matminer` | `matcalc[benchmark]` | **done**; `pkgs/matminer` — `tests/{featurizers,utils}` only, the data-retrieval suites hit external APIs |
| `redun` | `quacc[redun]` | **done**; `pkgs/redun` — `doCheck = false` (AWS-executor tests), `fancycompleter` removed |
| `phono3py` | `matcalc[phonon3]` | **done**; `pkgs/phono3py` — the phonopy sibling, scikit-build-core + nanobind + CMake |
| `rootstock` | `quacc[mlip]` | **done**; `pkgs/rootstock`, internal — `doCheck = false` (builds environments via `uv`) |
| `enumlib` | atomate2 `test_magnetic_orderings`, any `MagneticStructureEnumerator` | **done**; `pkgs/enumlib` — Fortran, not a Python package, top-level like `chemfiles`. Its `symlib` submodule is a second `fetchFromGitHub` because a submodule hash cannot be computed offline |
| `vise` | `pydefect`, `doped` — the `quacc[defects]` cluster | **done**; `pkgs/vise` at HEAD, 827 commits past its 2020 tag, because that is where the pymatgen-core refactoring landed. Ten undeclared imports added to `dependencies`, two dead `distutils` imports deleted. 25 tests dropped, 23 of them needing VASP's licensed POTCAR files |
| `trainstation` | `hiphive` — its only gap | **done**; `pkgs/trainstation`, internal. GitLab, like hiPhive |
| `hiphive` | `shakenbreak` | **done**; `pkgs/hiphive`, internal — `tests/unittests` only; `tests/integration` fits real force-constant models and takes minutes per file |
| `cmcrameri` | `doped` | **done**; `pkgs/cmcrameri`, internal — sixty colour-map `.txt` files, and the suite checks they are found |
| `matplotlib-label-lines` | `doped`, `pydefect` | **done**; `pkgs/matplotlib-label-lines`, internal. Dist `matplotlib-label-lines`, import `labellines`; its one test module is `labellines/test.py`, which pytest's default `python_files` matches neither way — the `pgtest` trap again |
| `pydefect` | `doped` | **done**; `pkgs/pydefect`, internal — built on `vise`, same group and same tagging habit (HEAD is 764 commits past v0.2.6, and `__init__.py` carries the real 0.10.1). Seven undeclared imports added, `emmet-core` the load-bearing one |
| `doped` | `shakenbreak` | **done**; `pkgs/doped`, internal. The `shakenbreak` requirement is dropped permanently rather than for bootstrapping — nix cannot express the cycle, every `import shakenbreak` in `doped/` is function-local, and shakenbreak is the half that declares the other. 873 MB of source, 414 MB of it recorded VASP output under `tests/`, none installed |

`pythonCatchConflictsPhase` did not, in the end, have anything to catch: `pymatgen-io-validation`
installs only `pymatgen/io/validation/`, and neither `pymatgen-core` nor `pymatgen` ships a
`pymatgen/io/__init__.py` — or any other file under that tree — for it to collide with. All
three are PEP 420 namespace packages and their installed file sets are disjoint, which is what
lets `python3.withPackages` merge them.

`emmet-core`'s suite **is** run, and it drove everything from `mp-pyrho` down. The first build
was 518 passed / 13 failed / 4 errors; the last, 792 passed / 4 failed. Every failure along the
way was a missing optional dependency, a network call, or a read-only path — not an emmet bug:

- `tests/io/test_pymatgen.py::test_imports` walks the whole add-on class map unconditionally, and
  `test_defects.py` / `test_migrationgraph.py` import `pymatgen.analysis.{defects,diffusion}` at
  module scope. Packaging `pymatgen-analysis-{alloys,defects,diffusion}` (and `mp-pyrho` under
  defects) covers all of them.
- `pyarrow` — emmet gates on `ARROW_COMPATIBLE`, and without it `test_thermo.py` referenced an
  unimported name and `test_trajectory.py::test_parquet` raised. It is in nixpkgs, so a check
  input.
- three tests reach the network (`test_from_url` → raw.githubusercontent.com; two robocrys
  molecule-name tests → PubChem). Deselected in `pkgs/emmet-core`.

`optimade` and `lobsterpy` are now packaged too, so `test_optimade` and `test_lobster` run.
`test_lobster`'s `add_coxxcar_to_task_document=True` cases write a parsed file back into
`test_files/lobster/`, which `sourceRoot` leaves read-only — `preCheck` widens it. `matgl` is
packaged but stays **out** of `emmet-core`'s check inputs: `test_similarity`'s
`M3GNetSimilarity` loads a pretrained model over the network, so it is better left as a clean
`skipif matgl is None`.

The add-ons and the two libraries then had their own suites to answer for, over a second and
third round:

- `pymatgen-analysis-diffusion`: a `StructureGraph.with_local_env_strategy` → `from_local_env_strategy`
  rename (module-scope, broke collection), then a stale INCAR reference string (`NELECT = 576`
  vs `576.0` — newer pymatgen writes it as a float). Both patched. 66 pass after.
- `pymatgen-analysis-defects`: 38/8/11 → all missing optional deps. `dscribe` and `ase` (in
  nixpkgs, now check inputs) fixed most; `pydefect`/`vise` (a large DFT-workflow tree) covers
  two `test_kumagai*` tests, deselected — the `kumagai` module guards on `__has_pydefect__`
  anyway. One more, `test_plotter`, is a deprecated pymatgen plotting function calling
  `axis.legend(handles=[], labels=[])` which matplotlib 3.11 rejects; deselected, the
  replacement `plotting` module is covered. 53 pass after.
- `matgl`: `matgl/config.py` makes `~/.cache/matgl` at import, so even `pythonImportsCheck`
  needed a writable `HOME` in `preBuild`.
- `optimade`: `ServerConfig` validates the license by fetching its SPDX URL; the shared test
  config's `license` is nulled in `postPatch`. 134 pass after.
- `lobsterpy`: `tests/featurize/` needs `mendeleev`, now packaged (`pkgs/mendeleev`, internal).
  `FeaturizeCharges` raises rather than skipping without it, so it is a check input rather than
  a soft dependency.

Everything else resolves: `pydash`, `flufl-lock`, `schedule`, `networkx`, `supervisor`, `typer`,
`rich`, `tomlkit`, `aioitertools`, `blake3`, `inflect`, `pyzmq`, `jsonlines`, `pandas` and the
rest are all in nixpkgs.

`mp-api` is **not** on the build path: it is wanted only by `matcalc` and by atomate2's optional
`mp` extra.

**pymatgen split in 2026, and that was the hard part — it was not a version bump.** Upstream
moved the core out into its own repository, which the `pymatgen` repo carries as a git submodule
at `pymatgen-core/` (so a plain `--depth 1` clone leaves that directory empty — see `.gitmodules`
there). "Metapackage" overstates what is left: `pymatgen`'s only *dependency* is
`pymatgen-core>=2026.7.16`, but it still ships `analysis` (bar the three phase-diagram modules),
`apps`, `cli`, `entries`, `ext` and `vis`. Both are PEP 420 namespace packages, neither ships
`pymatgen/__init__.py`, and no installed file path appears in both — which is what lets
`python3.withPackages` merge them.

nixpkgs is still on the pre-split monolith, 2025.10.7, which owns the same `pymatgen/…` import
paths, so `pymatgen-core` could not be added *beside* it. `overlays.materials` therefore
**replaces** nixpkgs' `pymatgen` with the pair. That is exactly what `pymatgenFor`'s own note
says must never happen to a *repair*, and the two are not in tension: `overlays.aiida` keeps its
repair local so that a consumer who wants only AiiDA is left alone, while `overlays.materials`
exists to deliver the split. `pymatgenFor` is now guarded on the version for that reason — under
a full composition its `pself.pymatgen` is already the 2026 pair, and its deselections name test
files that moved to the other half.

Two consequences worth knowing before touching this. The AiiDA family now builds against
pymatgen 2026 rather than 2025.10.7 whenever the overlays are composed, which
`default.nix` always does — `aiida-core`, `aiida-nwchem` and `aiida-gaussian` are the three that
take it. And `tests/aiida`'s `aiida-overlay-python-pin` had to start comparing against a fully
composed set, for the same reason `tests/chemtools`' `chemtools-python-pin` already did.

One further version conflict, unrelated to the split: `jobflow-remote` pins
`pymongo >= 4.4, < 4.11` where nixpkgs has 4.17.0. (`atomate2` wants `<= 4.17.0`, satisfied
exactly.) Expect `pythonRelaxDeps` plus a real check that its suite passes — pymongo 4.11 dropped
deprecated APIs, so this one may not be cosmetic.

**Treat every row below as unverified until you re-derive it.** Three entries in this table —
`deepmd-kit`, `fairchem-core`, and the `fairchem-data-*` set — were recorded as blocked on the
strength of a package's reputation rather than its `pyproject.toml`, and all three turned out to
need one or two ordinary packages; all three are packaged now, and none of them needed anything
the survey had not already read. The cost of checking is one `nix-instantiate --eval` over
`python313Packages`; the cost of not checking was months of a chain sitting closed.

| Not packaged | Blocker |
|---|---|
| `torch-sim` | `nvalchemi-toolkit-ops` (NVIDIA) is a **core** dependency, not in nixpkgs — and never surveyed, so "blocked" here means "unread". Queued in `docs/TODO.md` |
| `orb-models`, `mattersim`, `pet-mad` | same NVIDIA wall as `torch-sim` — `orb-models` lists `nvalchemi-toolkit-ops` as a core dep, `mattersim` lists `torch-sim-atomistic` (→ nvalchemi), `pet-mad` lists `nvalchemi-toolkit-ops` + `warp-lang`. These are the matcalc `orb` / `mattersim` / `petmad` extras |
| `openff-toolkit`, `openff-interchange`, `openff-qcsubmit`, `proteinbenchmark` | conda-first: pyproject declares **no** `dependencies`, the real ones are in `devtools/conda-envs/`. Needs seven packages nixpkgs lacks: `openff-units`, `openff-utilities`, `openff-nagl`, `openff-nagl-models`, `openff-forcefields`, `openff-amber-ff-ports`, `openmmforcefields`. **AmberTools is not a blocker** — it is a Python package in the existing `nixos-qchem` input (`pkgs/python-by-name/ambertools`), which carries no `openff-*` of its own. Coming from a flake input does put it under the cclib constraint, though: `overlays/` cannot reach it, so a dependant needs a defaulted argument and `meta.broken`, as `pkgs/harmonwig` does |
| `RMG-Py` | `python_requires >=3.9,<3.12` against this repo's 3.13/3.14 pins; large Cython build; Julia/ReactionMechanismSimulator at runtime |
| `fairchem-applications-*`, `fairchem-demo-ocpapi`, `fairchem-lammps` | **not blocked — queued**, and nothing downstream here asks for them. The remaining nine distributions of the monorepo; `fastcsp` wants `p-tqdm` and `ocx` wants `yellowbrick`, and those two packages are the only gaps in the set. See `docs/TODO.md` |
| `PsiDataViz` | uv workspace, never released, includes a React/TS frontend; only `packages/psidata` is plausible |
| ~~`crest`~~ | **Not a gap, and never was.** NixOS-QChem has it as `qchem.crest`, and `pkgs/aqme` has been reaching it through `final.crest or final.qchem.crest or null` all along. This row said "not in nixpkgs, feasible, just different work" and was reasoning from nixpkgs alone — check `package_list.json` in the nixos-qchem checkout before writing another row like it. See "Reusing NixOS-QChem" above |

## Template leftovers

`.github/workflows/build.yml` still contains the `<YOUR_REPO_NAME>` placeholder, which keeps the
NUR-update step disabled by its `if:` guard. Setting it means adding this repo to
[NUR's repos.json](https://github.com/nix-community/NUR/blob/master/repos.json) first, since the
step pings the update service with that name.

`cachixName` is set to `nur-berquist` and the cachix step is live. Its `if:` guard is now always
true — it survives only because the placeholder it compares against is the guard's own literal.
