{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  numpy,
  msgpack,
  requests,
  pyyaml,
  pydantic,
  pydantic-settings,
  zstandard,
  apsw,
  qcelemental,
  tabulate,
  tqdm,
  pandas,
  pyjwt,
  dateutils,
  pytz,
  # pyarrow,
  # pytestCheckHook,
  # deepdiff,
  # qcfractal,
  # qcarchivetesting,
}:

buildPythonPackage rec {
  pname = "qcportal";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-fgY2i9HhLpUhsnK5nX6ovMVTj6QRKPTZtDVQv9OLoKw=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    numpy
    msgpack
    requests
    pyyaml
    pydantic
    pydantic-settings
    zstandard
    apsw
    qcelemental
    tabulate
    tqdm
    pandas
    pyjwt
    dateutils
    pytz
  ];

  # nativeCheckInputs = [
  #   pytestCheckHook
  #   deepdiff
  #   # qcfractal
  #   # qcarchivetesting
  # ];

  pythonImportsCheck = [ "qcportal" ];

  meta = with lib; {
    description = "Python client for QCFractal / QCArchive servers";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
