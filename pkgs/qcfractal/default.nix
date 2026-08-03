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
  pythonAtLeast,
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
    # Inherited from qcportal, which cannot import on 3.14; see the note there.
    # meta.broken does not propagate to dependents, and a broken dependency
    # throws at *evaluation* time when a dependent is built, so each package
    # that pulls in qcportal has to carry the marking itself.
    broken = pythonAtLeast "3.14";
    description = "QCFractal server - distributed quantum chemistry compute & database";
    homepage = "https://github.com/MolSSI/QCFractal";
    # The console script is qcfractal-server, not qcfractal; without this
    # lib.getExe (used by nixos-modules/qcfractal-server.nix) silently falls
    # back to $out/bin/qcfractal, which does not exist.
    mainProgram = "qcfractal-server";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
