{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  cp2k-output-tools,
  click,
  tabulate,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-gaussian-datatypes";
  version = "0.5.1";
  pyproject = true;

  # aiida-cp2k depends on this unbounded, so any recent release will do.
  # PEP 625 underscore in the sdist name, hence the explicit pname.
  src = fetchPypi {
    pname = "aiida_gaussian_datatypes";
    inherit version;
    hash = "sha256-18S4U+S8oIDU77w4pBPq8OShbSQEaJmkTUsNvX1AlUM=";
  };

  build-system = [ setuptools ];

  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    cp2k-output-tools
    click
    tabulate
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
  ];

  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [ "aiida_gaussian_datatypes" ];

  meta = {
    description = "AiiDA data plugin for Gaussian basis sets and pseudopotentials";
    homepage = "https://github.com/aiidateam/aiida-gaussian-datatypes";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
