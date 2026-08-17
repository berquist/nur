{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  pg8000,

  # tests
  pytestCheckHook,
  postgresql,
}:

buildPythonPackage rec {
  pname = "pgtest";
  version = "1.3.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-7bte1fXEaub2pY7v/Pny7xRnv+5Ot1PwvKSrLLMC7pE=";
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
  nativeCheckInputs = [
    pytestCheckHook
    postgresql
  ];

  pythonImportsCheck = [ "pgtest" ];

  meta = {
    description = "Creates a temporary, local PostgreSQL cluster for unit testing";
    homepage = "https://github.com/jamesnunn/pgtest";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
