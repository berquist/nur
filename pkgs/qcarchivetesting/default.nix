# qcarchivetesting - pytest harnesses and fixtures for testing QCArchive
# components.  Not needed for production; only used when running the
# QCFractal test suite or writing integration tests.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  qcportal,
  qcfractal,
  qcfractalcompute,
  pytest,
}:

buildPythonPackage rec {
  pname = "qcarchivetesting";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-HWTxXH9LX2ZSjmTmsSnZv+L5K6xwZlxuybevr3YddbM=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    qcportal
    qcfractal
    qcfractalcompute
    pytest
  ];

  # Tests require a live PostgreSQL instance; skip at build time.
  doCheck = false;

  pythonImportsCheck = [ "qcarchivetesting" ];

  meta = with lib; {
    description = "pytest harnesses for testing QCArchive / QCFractal components";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
