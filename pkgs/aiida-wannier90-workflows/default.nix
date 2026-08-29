{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-pseudo,
  aiida-quantumespresso,
  aiida-wannier90,
  click,
  colorama,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-wannier90-workflows";
  version = "3.0.0-unstable-2026-08-20";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-wannier90-workflows";
    rev = "000cabe9c9c3adefa80d3d7d1b2e8f4d9427b870";
    hash = "sha256-OgGtOuo2xOmY2EpsVKBzfN9YjVEPJ1HLI3Ukh5bvW4g=";
  };

  build-system = [ flit-core ];

  # aiida-wannier90 is declared as a direct URL:
  #
  #   "aiida-wannier90 @ git+https://github.com/aiidateam/aiida-wannier90.git@v2.2.0"
  #
  # **pythonRelaxDeps cannot touch that.**  It rewrites version specifiers, and
  # a PEP 508 direct reference has none — the whole requirement is a URL, which
  # the metadata check then tries to resolve against a distribution named by
  # that URL rather than by name.  Rewriting it to the bare name is what lets
  # ../aiida-wannier90 satisfy it, and the version it pins, v2.2.0, is exactly
  # what that package builds.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '"aiida-wannier90 @ git+https://github.com/aiidateam/aiida-wannier90.git@v2.2.0",' \
        '"aiida-wannier90",'
  '';

  # aiida-core for the pre-release reason in ../aiida-orca/default.nix, and
  # aiida-quantumespresso because the pin is `>=4.4,<5` while ../aiida-quantumespresso
  # is 5.0.0:
  #
  #   Checking runtime dependencies for aiida_wannier90_workflows-3.0.0-py3-none-any.whl
  #     - aiida-quantumespresso<5,>=4.4 not satisfied by version 5.0.0
  #
  # An upper bound rather than a pre-release quirk, so this one is a real
  # question rather than a formality: the workflows call
  # `PwBaseWorkChain`/`PwCalculation` and the `get_builder_from_protocol`
  # helpers, none of which 5.0 moved.  The suite is what confirms it.
  pythonRelaxDeps = [
    "aiida-core"
    "aiida-quantumespresso"
  ];

  dependencies = [
    aiida-core
    aiida-pseudo
    aiida-quantumespresso
    aiida-wannier90
    click
    colorama
  ];

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module; see ../aiida-core/default.nix for what that needs
    # patched, and ../pgtest for why postgresql accompanies pgtest.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # No Quantum ESPRESSO or wannier90 binary: the suite builds workchain inputs
  # and asserts on them, in the same way ../aiida-wannier90's does.
  pythonImportsCheck = [
    "aiida_wannier90_workflows"
    "aiida_wannier90_workflows.calculations"
    "aiida_wannier90_workflows.workflows"
    "aiida_wannier90_workflows.utils"
  ];

  meta = {
    description = "Automated Wannierisation workflows built on aiida-wannier90 and Quantum ESPRESSO";
    homepage = "https://github.com/aiidateam/aiida-wannier90-workflows";
    license = lib.licenses.mit;
    mainProgram = "aiida-wannier90-workflows";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
