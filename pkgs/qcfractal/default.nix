# qcfractal - the QCFractal server (web API + database layer).
# Provides the `qcfractal-server` CLI entry point.
#
# Optional extras (not included in the default build):
#   services  - geometric, basis_set_exchange (for server-side optimisation services)
#   geoip     - geoip2 (access-log geo-tagging)
#   snowflake - temporary in-process server for testing
#   s3        - boto3 (S3 result storage)

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
  pname = "qcfractal";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+6evn7D/PYNUJMbmUiDsCy8BHiYc6S5FxjcRwFrrxdk=";
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
  #   sqlalchemy
  #   alembic
  #   psycopg2
  #   pydantic
  #   pydantic-settings
  #   pyyaml
  #   bcrypt
  #   cryptography
  #   flask
  #   flask-jwt-extended
  #   waitress
  #   numpy
  # ];

  # dontBuild = true;

  # qcfractal imports its own top-level package; the CLI script is installed
  # separately via the wheel's entry_points.
  pythonImportsCheck = [ "qcfractal" ];

  meta = with lib; {
    description = "QCFractal server - distributed quantum chemistry compute & database";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
