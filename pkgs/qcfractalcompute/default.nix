{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  qcportal,
  qcengine,
  parsl,
  pydantic,
  pydantic-settings,
  pyyaml,
  numpy,
  # pytestCheckHook,
  # qcarchivetesting,
}:

buildPythonPackage rec {
  pname = "qcfractalcompute";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-QxAvT7GEBogE8LQa5nIp6//p37qvOX3aTfjOJVVxu/I=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    qcportal
    qcengine
    parsl
    pydantic
    pydantic-settings
    pyyaml
    numpy
  ];

  # nativeCheckInputs = [
  #   pytestCheckHook
  #   qcarchivetesting
  # ];

  pythonImportsCheck = [ "qcfractalcompute" ];

  meta = with lib; {
    description = "QCFractalCompute - compute manager / worker for QCFractal";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
