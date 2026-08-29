{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  aiida-core,
  aiida-pythonjob,
  phonopy,
  seekpath,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pytest-timeout,
  pgtest,
  postgresql,
  procps,
  ase,
  coreutils,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-phonopy";
  version = "1.8.0-unstable-2026-08-17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiida-phonopy";
    repo = "aiida-phonopy";
    rev = "f97e03a8a6055aade7b5806e72374015f54e6023";
    hash = "sha256-cA9tCmHiGQ2JHHk2LYeIEMG+IY8v0x74cgx+OLo5Shc=";
  };

  build-system = [ hatchling ];

  # See ../aiida-orca/default.nix.  `aiida-pythonjob~=0.5` is satisfied by
  # ../aiida-pythonjob, so aiida-core would be the only pin needing a lift —
  # except that `phonopy~=4.0` holds only on two of the three CI channels.
  # nixpkgs-unstable and nixos-unstable carry phonopy 4.4.0; nixos-26.05 is a
  # major behind at 3.5.1, and there `pythonRuntimeDepsCheckHook` stops the
  # build before it installs anything:
  #
  #   - phonopy~=4.0 not satisfied by version 3.5.1
  #
  # The pin is about phonopy's *command line*, not its Python API, and upstream
  # says so — aiida-phonopy's own CHANGELOG for v1.8.0 reads "Minor release to
  # support phonopy v4.0, as it introduces some breaking changes in the CLI.
  # The API would be in principle backward compatible, but in order to not
  # create confusion, we support the version that support both API and CLI."
  #
  # That checks out against the two tags.  Every symbol this plugin imports —
  # `Phonopy`, `PhonopyAtoms`, `estimate_supercell_matrix`, `get_physical_units`,
  # `symmetrize_borns_and_epsilon`, `read_force_constants_hdf5` and
  # `write_force_constants_to_hdf5` — exists at v3.5.1 as well as v4.4.0.  The
  # two edits in upstream's v4 commit (`abfdd7d`) that look like API breaks are
  # deliberately backward compatible: `phonopy.__version__` is re-exported by
  # v3.5.1's `__init__.py`, and it is the *old* `from phonopy.version import
  # __version__` that 4.x breaks; and `--config` is already in v3.5.1's
  # `phonopy/cui/phonopy_argparse.py`.  phonopy 4.0's one behavioural API
  # change, `primitive_matrix` defaulting to `"auto"`, never reaches here —
  # `data/raw.py` passes `primitive_matrix` explicitly at both `Phonopy(...)`
  # sites and picks its own default before storing it.
  #
  # What does differ is what the name `phonopy` means as a *program*: in 3.x it
  # is the old full CLI and `phonopy-load` is the loader, while 4.0 split them
  # so that `phonopy` is the loader and `phonopy-init` does the setup.  That is
  # a property of the executable an AiiDA `Code` points at on a compute
  # resource, chosen by the user and unrelated to the Python phonopy in this
  # closure — so it is not a reason to keep the package unbuildable on a whole
  # channel.  A 26.05 user pointing a `Code` at a phonopy 3 binary will get the
  # wrong CLI, but that was already true of the version they installed there.
  pythonRelaxDeps = [
    "aiida-core"
    "phonopy"
  ];

  dependencies = [
    aiida-core
    aiida-pythonjob
    phonopy
    seekpath
  ];

  # The code fixture defaults to `filepath='/bin/true'`, which a build sandbox
  # does not have.  See ../aiida-orca/default.nix.
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail "filepath='/bin/true'" "filepath='${coreutils}/bin/true'"
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions
    pytest-timeout

    # conftest.py names the supported `aiida.tools.pytest_fixtures`; see
    # ../pgtest for why postgresql accompanies pgtest.
    pgtest
    postgresql

    # The `tests` extra asks for ase, which the structure fixtures use to build
    # the cells the workflows are run over.
    ase

    # tests/workflows/test_ase.py really runs `PhonopyAseWorkChain`, which
    # submits a PythonJob through the `core.direct` scheduler, and that reads
    # its joblist from `ps`.  Without it the workchain's forces step is
    # retrieved early and the two tests fail as a bare `assert False`, with
    #
    #   Warning in _parse_joblist_output ... 'bash: line 1: ps: command not found'
    #   output parser returned exit code<310>: The output file could not be read
    #
    # in the captured log.  See ../aiida-cp2k/default.nix.
    procps
  ];

  # The two workflow tests need a broker, and this package's conftest does not
  # ask for one.
  #
  # `PhonopyAseWorkChain` submits a PythonJob from inside itself, and
  # tests/conftest.py names `aiida.tools.pytest_fixtures` without overriding
  # `aiida_profile` — so the profile has no process control backend at all, the
  # submission is never picked up, and the workchain terminates seconds later
  # with the child holding no `retrieved` output:
  #
  #   NotExistentAttributeError: Node<117> does not have an output with link
  #   label 'retrieved'
  #   KeyError: 'output_phonopy'
  #
  # ../aiida-shell, ../aiida-workgraph, ../aiida-pythonjob and ../aiida-restapi
  # all override that fixture to ask for RabbitMQ, which this repo rewrites to
  # `core.zeromq`; aiida-phonopy simply relies on whatever its CI provides.
  # Supplying it here would mean writing the missing fixture *and* marking both
  # tests with `started_daemon_client`, which is inventing two pieces of
  # upstream rather than adapting one.  The other fifty-three tests — the raw
  # data model, the parsers, the validators — run.
  disabledTestPaths = [
    "tests/workflows/test_ase.py::test_run"
    "tests/workflows/test_ase.py::test_run_with_calculator_factory"
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  #
  # aiida-pythonjob's config.py runs `load_config()` at module scope, and that
  # calls aiida-core's `get_config()`, which raises rather than creating one:
  #
  #   aiida.common.exceptions.MissingConfigurationError: configuration file
  #   /build/tmp.../.aiida/config.json does not exist
  #
  # HOME and AIIDA_PATH are not enough on their own, because nothing in a build
  # ever runs `verdi`, which is what would normally create the file.  This package imports
  # aiida_pythonjob, so it inherits the requirement.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
    python -c 'from aiida.manage.configuration import get_config; get_config(create=True)'
  '';

  pythonImportsCheck = [
    "aiida_phonopy"
    "aiida_phonopy.calculations"
    "aiida_phonopy.data"
    "aiida_phonopy.parsers"
    "aiida_phonopy.workflows"
  ];

  meta = {
    description = "AiiDA plugin for phonopy, for phonon calculations";
    homepage = "https://github.com/aiida-phonopy/aiida-phonopy";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
