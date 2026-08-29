{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  voluptuous,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  bash,
  gromacs,
  plumed,
  procps,
  which,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-gromacs";
  version = "2.2.2-unstable-2026-08-27";
  pyproject = true;

  # Two commits past the 2.2.2 tag, which upstream writes without a leading `v`.
  # Not fetchPypi: the sdist drops `tests/`, and the CLI tests are half the
  # suite.  See ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "CCPBioSim";
    repo = "aiida-gromacs";
    rev = "e848bbc2a18af220306a6a53f1f88681b432c1fd";
    hash = "sha256-PfzFcnkc9F0hwlwoya0qvzB+UIL4bK32PqIrUeuQn4U=";
  };

  build-system = [ flit-core ];

  # `flit_core >=4,<5` against nixpkgs' 3.12.0.  pypaBuildHook builds with
  # `--no-isolation`, so `build` checks the requirement against the environment
  # it was given and stops at "Missing dependencies" rather than fetching one —
  # this is a build failure, not a warning.  flit_core 4 changed nothing this
  # package uses: the metadata is a plain PEP 621 table with a `dynamic`
  # version read from `aiida_gromacs/__init__.py`, which 3.2 has supported
  # since it added PEP 621 support.
  #
  # pythonRelaxDeps cannot do this.  It rewrites the *distribution's* declared
  # dependencies in the built metadata, and this is a build-system requirement,
  # read from pyproject.toml before any of that exists.
  # The second and third rewrites uncomment what upstream already wrote down,
  # and the reason is a property of the packaged PLUMED rather than of these
  # tests.  **nixpkgs' plumed is built without MPI support** — its derivation
  # takes blas and nothing else — so a PLUMED-patched mdrun works on exactly
  # one rank.  Running the tests' own tpr and plumed.dat through `gmx mdrun
  # -plumed` directly says so, at four rank counts:
  #
  #   (default, 128 tMPI)  exit 139  double free or corruption (fasttop)
  #   -ntmpi 1             exit 0    HILLS, COLVAR and the .gro all written
  #   -ntmpi 2             exit 1    PLMD::Communicator::Set_comm: "you are
  #   -ntmpi 4             exit 1      trying to use an MPI function, but
  #                                     PLUMED has been compiled without MPI
  #                                     support"
  #
  # So two ranks and four fail cleanly and 128 fails as a crash — the same
  # missing MPI support, once with a diagnostic and once without.  A stock
  # thread-MPI gmx picks a rank per core, which is why the tests hit the crash
  # rather than the message, and why the file list the MdrunParser complains
  # about has a .log and empty .edr/.trr and no HILLS.
  #
  # `-ntmpi 1` is therefore not papering over a defect in this plugin: it is
  # the only mode the packaged PLUMED can run in, and it is what both call
  # sites already carry commented out with "turn off omp and mpi for gmx
  # patched with plumed" beside them.  What it does mean is that these three
  # tests cover serial metadynamics only.
  #
  # Covering a parallel one is a nixpkgs change first — plumed needs an
  # `enableMpi`, drafted in ../../.scratch/nixpkgs-plumed-mpi.patch — and then
  # both halves here:
  #
  #   gromacs.override {
  #     enablePlumed = true;
  #     enableMpi = true;
  #     plumed = plumed.override { enableMpi = true; };
  #   }
  #
  # which also stops being substitutable, since nothing has built that
  # combination before.
  #
  # Uncommented as one line each rather than two, because the `# "1",` that
  # follows both is not unique to the plumed test and substituteInPlace
  # replaces every occurrence — uncommenting it in the neighbouring test would
  # leave a stray argument after a `-ntmpi` that is still commented out.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["flit_core >=4,<5"]' 'requires = ["flit_core >=3.2,<5"]'

    substituteInPlace tests/test_calcs_mdrun.py \
      --replace-fail \
        '# "ntmpi": "1", # turn off omp and mpi for gmx patched with plumed' \
        '"ntmpi": "1",'

    substituteInPlace tests/test_cli_mdrun.py \
      --replace-fail \
        '# "-ntmpi", # turn off mpi for gmx patched with plumed' \
        '"-ntmpi", "1",'
  '';

  # See ../aiida-orca/default.nix.  Mandatory rather than cosmetic here: the
  # pin is `aiida-core>=2.8.0,<=2.8.1`, an upper bound that our 2.10.0.dev0
  # fails on its own terms, not merely as a pre-release.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    voluptuous
  ];

  # `$out/bin` because half the suite is CLI tests that reach this package's own
  # console scripts through `subprocess.check_output(["gmx_editconf", ...])`.
  # Same idiom, same reason, as ../aiida-pseudo/default.nix.
  #
  # PLUMED_KERNEL is belt and braces rather than the fix it was first taken
  # for.  `gmx --version` on the overridden build reports
  # `2024.2-plumed_2.10.1` and `gmx mdrun -h` lists `-plumed`, so the patch is
  # in the binary already, and a serial run writes HILLS and COLVAR whether or
  # not this is set.  It costs nothing and covers the runtime-linking case,
  # since nixpkgs takes plumed as a *nativeBuildInput* of gromacs, which is the
  # arrangement a runtime patch would need.
  preCheck = ''
    export PATH="$out/bin:$PATH"
    export PLUMED_KERNEL="${plumed}/lib/libplumedKernel.so"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # conftest.py names `aiida.manage.tests.pytest_fixtures`, the deprecated
    # module, whose profile is a real PostgreSQL one.  See ../pgtest for why
    # postgresql is listed alongside it.
    pgtest
    postgresql

    # The suite runs GROMACS for real: `aiida.engine.run` on nine calculation
    # plugins, each through `aiida_local_code_factory(executable="gmx")`, which
    # resolves the name on PATH.  `bash` is the executable behind the second
    # code fixture, and `which` is how aiida-core's local transport resolves
    # both.
    #
    # `enablePlumed`, which nixpkgs defaults to false, because three of the
    # thirty-three tests drive metadynamics: test_process_plumed,
    # test_file_name_match_plumed and test_launch_mdrun_plumed run `gmx mdrun
    # -plumed` and their parser then looks for HILLS and COLVAR, which a stock
    # gmx never writes:
    #
    #   Found files '[..., 'mdrun.out', 'plumed_mdrun_prod.log']', expected to
    #   find '[..., 'HILLS', 'COLVAR']'
    #
    # The override is cheaper than it looks: cache.nixos.org has
    # gromacs-2024.2 built this way, so it substitutes rather than compiling.
    # What it does change is the GROMACS version — nixpkgs' enablePlumed pins
    # the 2024 source, where the default is 2026 — so these three tests run
    # against a different gmx from the other thirty.
    (gromacs.override { enablePlumed = true; })

    # plumed itself, for $PLUMED_KERNEL — see preCheck.
    plumed
    bash
    which

    # The `direct` scheduler reads its joblist from `ps`.  Without it aiida
    # retrieves the working directory before `gmx` has written its outputs, and
    # twelve of the thirty-three tests fail on the consequence rather than the
    # cause — `KeyError: 'stdout'`, `assert 300 == 0`, and parser errors naming
    # the files that were not there yet.  See ../aiida-cp2k/default.nix.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_gromacs"
    "aiida_gromacs.calculations"
    "aiida_gromacs.parsers"
    "aiida_gromacs.workflows"
  ];

  meta = {
    description = "AiiDA plugin for running GROMACS molecular dynamics simulations";
    homepage = "https://github.com/CCPBioSim/aiida-gromacs";
    license = lib.licenses.mit;
    # Nine console scripts, one per GROMACS subcommand plus `createarchive`.
    # `genericMD` is the general one — it runs an arbitrary command under
    # provenance rather than wrapping a particular `gmx` subcommand — so it is
    # the sensible target for `lib.getExe`, which would otherwise fall back to
    # the package name and produce a path that does not exist.
    mainProgram = "genericMD";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
