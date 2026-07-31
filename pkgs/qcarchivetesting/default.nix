# pkgs/qcarchivetesting.nix
#
# qcarchivetesting – pytest harnesses and fixtures for testing QCArchive
# components.  This package is NOT needed for production deployments; it is
# only useful if you want to run the QCFractal test suite or write integration
# tests against a live (or snowflake) server.
#
# Dependencies:
#   qcportal, qcfractal, qcfractalcompute (same version)
#   pytest

{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  flask,
  flask-jwt-extended,
  flask-cors,
  waitress,
  bcrypt,
  sqlalchemy,
  alembic,
  psycopg2,
  qcportal,
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
    flask
    flask-jwt-extended
    flask-cors
    waitress
    bcrypt
    sqlalchemy
    alembic
    psycopg2
    qcportal
  ];

  # propagatedBuildInputs = [
  #   qcportal
  #   qcfractal
  #   qcfractalcompute
  #   pytest
  # ];

  # dontBuild = true;

  # Don't run the test suite as part of the package build – that would require
  # a running PostgreSQL instance.
  doCheck = false;

  pythonImportsCheck = [ "qcarchivetesting" ];

  meta = with lib; {
    description = "pytest harnesses for testing QCArchive / QCFractal components";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
