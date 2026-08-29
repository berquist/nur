{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  ase,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
  coreutils,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-ase";
  version = "3.0.0-unstable-2024-09-05";
  pyproject = true;

  # One commit past v3.0.0, and not fetchPypi: `[tool.flit.sdist] exclude` drops
  # `tests/`, so the sdist would give a check phase with nothing to collect.
  src = fetchFromGitHub {
    owner = "aiidaplugins";
    repo = "aiida-ase";
    rev = "e7bc0dc01cae8dd7089db5238f7ab41ace9cb7a2";
    hash = "sha256-rYXO8z0AJ/SbxrHdvxmlqtAZ7cfIBa03X4CmSilsr2I=";
  };

  build-system = [ flit-core ];

  # See ../aiida-orca/default.nix: our aiida-core is a pre-release and does not
  # satisfy `aiida-core~=2.0` under PEP 440 without an opt-in.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    ase
  ];

  # Two rewrites.
  #
  # `filepath_executable='/bin/true'` in tests/conftest.py, against a build
  # sandbox that has only /bin/sh.  See ../aiida-orca/default.nix.
  #
  # The second is a stale pytest-regressions reference, the same species of
  # failure as the `matdyn` one in ../aiida-quantumespresso/default.nix and for
  # the same underlying reason: aiida-core here is `main`, and a reference
  # recorded against a release does not always survive that.
  #
  # The gpaw parser returns a TrajectoryData, and `.base.attributes.all` on one
  # now carries a `pbc` key that it did not when tests/parsers/test_ase/
  # test_default_gpaw.yml was recorded:
  #
  #     @@ -81,6 +81,10 @@
  #        array|steps:
  #        - 1
  #     +  pbc:
  #     +  - true
  #     +  - true
  #     +  - true
  #        symbols:
  #
  # Only the trajectory block moved.  The `structure:` block in the same file
  # keeps the `pbc1`/`pbc2`/`pbc3` triple it always had, which is why
  # test_default_ase — whose reference has only that block — passes untouched.
  #
  # The parser is unchanged and the three values are correct for a periodic
  # cell, so the recorded file is what is stale.  `--force-regen` is not the fix
  # for the reason given in aiida-quantumespresso: it would rewrite every
  # reference in the suite and hide any that had drifted for a real reason.
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail "'/bin/true'" "'${coreutils}/bin/true'"

    substituteInPlace tests/parsers/test_ase/test_default_gpaw.yml \
      --replace-fail '  array|steps:
      - 1
      symbols:' '  array|steps:
      - 1
      pbc:
      - true
      - true
      - true
      symbols:'
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, whose profile is a real PostgreSQL one.  See ../pgtest
    # for why postgresql is listed alongside it.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # gpaw is deliberately *not* a check input, although nixpkgs carries it in the
  # Python set and two parser tests are named after it.  Nothing here imports
  # gpaw: `ase.gpaw` is an entry point into a parser of this package's own, the
  # calculation tests assert on the generated input file, and the parser tests
  # replay the stored outputs under tests/parsers/fixtures/.  Adding it would
  # buy a large closure and change nothing that runs.
  pythonImportsCheck = [
    "aiida_ase"
    "aiida_ase.calculations"
    "aiida_ase.parsers"
    "aiida_ase.workflows"
  ];

  meta = {
    description = "AiiDA plugin for the Atomic Simulation Environment (ASE) and GPAW";
    homepage = "https://github.com/aiidaplugins/aiida-ase";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
