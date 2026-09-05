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
  `jobflow-remote`, `pubchempy`, and both halves of upstream pymatgen's 2026 split,
  `pymatgen-core` and `pymatgen`. Plus three carried for a dependant alone and not re-exported:
  `mongomock-persistence` (fireworks'), `mongomock-ng` (maggma's) and `monty`, a backport that
  exists only because `pymatgen-core` needs a version no channel here ships yet.
  **This is the one overlay that replaces packages nixpkgs already has** — `pymatgen`, because
  upstream split it and the two layouts cannot coexist, and `monty` on the legs that are behind.
  Taking `overlays.materials` means taking both; see the cclib-style discussion at the overlay
  itself and in `pkgs/pymatgen-core/default.nix`. See "Deferred packaging" below for what is
  still gated.

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

## Where the explanations live

Every non-obvious decision here is commented **at the code it governs**, because that is where
it will be read. Do not copy those explanations into this file; add a pointer instead.

| Question | Read |
|---|---|
| How do I check anything from inside the Claude Code sandbox? | the `no-daemon-check` skill, `scripts/no-daemon-check.sh` |
| Where does a `fetchFromGitHub` hash come from with no network and no daemon? | `scripts/offline-src-hash.sh` (the header comment), `just hash-src` |
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

## Architecture

### Two entry points, one source of truth

`default.nix` is the NUR entry point and the canonical package list. `flake.nix` and
`overlay.nix` both derive from it:

- `flake.nix` → `legacyPackages` = `import ./default.nix`; `packages` = the derivations
  filtered out of that.
- `overlay.nix` → the same attrset minus the *reserved* keys.

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

**The materials-project chain.** `atomate2` is the near-term target;
`pymatgen-analysis-defects`, `matgl`, `matcalc` and `quacc` follow. Reading those targets' own
`pyproject.toml` against the locked nixpkgs, this is where the survey stands:

| Missing | Wanted by | Status |
|---|---|---|
| `maggma` | `jobflow` — its only gap | **done** |
| `qtoolkit` | `jobflow-remote` — its only gap | **done**; `dependencies = []`, which is why it went first |
| `mongomock-ng` | `maggma` | **done**; *not* the `mongomock` nixpkgs already has |
| `pubchempy` | `emmet-core` | **done** |
| `monty` | `pymatgen-core` | **done**; a backport, guarded — see `pkgs/monty/default.nix` |
| `pymatgen-core` | everything left | **done**; the split below |
| `pymatgen` | `emmet-core`, `atomate2` | **done**; the other half of the same split |
| `pymatgen-io-validation` | `emmet-core` | next; needs `pymatgen-core>=2026.4.16`, which is now here |
| `emmet-core` | `atomate2`, `quacc` | blocked on the above; `materialsproject/emmet`, in `emmet-core/` |

One thing to expect from `pymatgen-io-validation`: it installs *into* the
`pymatgen.io.validation` namespace, so it shares a package directory with `pymatgen-core` and
will meet `pythonCatchConflictsPhase`.

Everything else resolves: `pydash`, `flufl-lock`, `schedule`, `networkx`, `supervisor`, `typer`,
`rich`, `tomlkit`, `aioitertools`, `blake3`, `inflect`, `pyzmq`, `jsonlines`, `pandas` and the
rest are all in nixpkgs.

`mp-pyrho` and `mp-api` are **not** on this path, whatever an earlier version of this section
said: `mp-pyrho` is wanted by `pymatgen-analysis-defects` alone, and `mp-api` only by `matcalc`
and by atomate2's optional `mp` extra.

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

| Not packaged | Blocker |
|---|---|
| `torch-sim` | `nvalchemi-toolkit-ops` (NVIDIA) is a **core** dependency, not in nixpkgs |
| `ShakeNBreak` | needs `doped` (missing, large) and `hiphive` (missing), on top of the chain above |
| `openff-toolkit`, `openff-interchange`, `openff-qcsubmit`, `proteinbenchmark` | conda-first: pyproject declares **no** `dependencies`, the real ones are in `devtools/conda-envs/`. Needs seven packages nixpkgs lacks: `openff-units`, `openff-utilities`, `openff-nagl`, `openff-nagl-models`, `openff-forcefields`, `openff-amber-ff-ports`, `openmmforcefields`. **AmberTools is not a blocker** — it is a Python package in the existing `nixos-qchem` input (`pkgs/python-by-name/ambertools`), which carries no `openff-*` of its own. Coming from a flake input does put it under the cclib constraint, though: `overlays/` cannot reach it, so a dependant needs a defaulted argument and `meta.broken`, as `pkgs/harmonwig` does |
| `RMG-Py` | `python_requires >=3.9,<3.12` against this repo's 3.13/3.14 pins; large Cython build; Julia/ReactionMechanismSimulator at runtime |
| `fairchem` | 13-distribution monorepo, torch plus pretrained model weights |
| `PsiDataViz` | uv workspace, never released, includes a React/TS frontend; only `packages/psidata` is plausible |
| `crest` | Fortran/meson with vendored subprojects; not in nixpkgs. Feasible, just different work — `tblite` and `xtb` are already there to build against |

## Template leftovers

`.github/workflows/build.yml` still contains the `<YOUR_REPO_NAME>` placeholder, which keeps the
NUR-update step disabled by its `if:` guard. Setting it means adding this repo to
[NUR's repos.json](https://github.com/nix-community/NUR/blob/master/repos.json) first, since the
step pings the update service with that name.

`cachixName` is set to `nur-berquist` and the cachix step is live. Its `if:` guard is now always
true — it survives only because the placeholder it compares against is the guard's own literal.
