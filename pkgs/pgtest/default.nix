{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  pg8000,

  # tests
  pytestCheckHook,
  postgresql,
  psycopg2,
  sqlalchemy,
}:

buildPythonPackage rec {
  pname = "pgtest";
  version = "1.3.2";
  pyproject = true;

  # The sdist has no `test/`, so pytestCheckPhase collected zero items and
  # exited 5.  Upstream's tag has no `v` prefix.
  src = fetchFromGitHub {
    owner = "jamesnunn";
    repo = "pgtest";
    tag = version;
    hash = "sha256-iqrx/U3tjmggQS2aWORjHscqSn0e+8ognCZnTTNZ4vI=";
  };

  build-system = [ setuptools ];

  dependencies = [ pg8000 ];

  # pgtest is a library, not a program: consumers do `from pgtest.pgtest import
  # PGTest` and it shells out to initdb, pg_ctl and postgres from the *calling*
  # process's PATH.  There is no console script here to wrap, so nothing this
  # derivation can do makes those binaries reachable — every derivation whose
  # checkPhase uses pgtest, directly or through
  # aiida.manage.tests.pytest_fixtures, has to list `postgresql` in its own
  # nativeCheckInputs.  Without it pgtest fails with "Could not find PostgreSQL
  # executables", because the paths it searches (/usr/lib/postgresql/*/bin and
  # friends) exist on no NixOS machine.
  #
  # The suite itself connects three different ways — psycopg2, pg8000 and
  # SQLAlchemy — because that is the compatibility pgtest promises, so all
  # three are check inputs even though only pg8000 is a runtime dependency.
  nativeCheckInputs = [
    pytestCheckHook
    postgresql
    psycopg2
    sqlalchemy
  ];

  pythonImportsCheck = [ "pgtest" ];

  meta = {
    description = "Creates a temporary, local PostgreSQL cluster for unit testing";
    homepage = "https://github.com/jamesnunn/pgtest";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
