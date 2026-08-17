{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  click,
  pydantic,
  requests,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-pseudo";
  version = "1.7.2";
  pyproject = true;

  # The lower bound aiida-quantumespresso pins (`>=1.7.2,<2`); aiida-cp2k asks
  # for `~=1.2`, which this satisfies.
  src = fetchPypi {
    pname = "aiida_pseudo";
    inherit version;
    hash = "sha256-bajniRfnqB7J2Qq5hwW1boWJroWrUmtNiwLXoXeP/Q4=";
  };

  build-system = [ flit-core ];

  # aiida-core here is a 2.10.0.dev0 snapshot, and a pre-release does not
  # satisfy a `>=2.x` specifier under PEP 440 unless pre-releases are opted in.
  # Every AiiDA plugin in this repo needs this for the same reason.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    click
    pydantic
    requests
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix: importing aiida creates $HOME/.aiida, and
  # /homeless-shelter does not exist.  genericBuild runs every phase in one
  # shell, so this covers pythonImportsCheck as well as checkPhase.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # `aiida-pseudo install <family>` downloads pseudopotential archives from
  # Materials Cloud and the SSSP/PseudoDojo publishers.  Those tests are the
  # network-bound ones; the parsing, family and CLI tests below are not.
  disabledTests = [
    "test_install_sssp"
    "test_install_pseudo_dojo"
    "test_download_sssp"
    "test_download_pseudo_dojo"
  ];

  pythonImportsCheck = [
    "aiida_pseudo"
    "aiida_pseudo.data.pseudo"
    "aiida_pseudo.groups.family"
  ];

  meta = {
    description = "AiiDA plugin for managing pseudopotentials";
    homepage = "https://github.com/aiidateam/aiida-pseudo";
    license = lib.licenses.mit;
    mainProgram = "aiida-pseudo";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
