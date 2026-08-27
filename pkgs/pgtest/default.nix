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

  # Naming the file is what makes it collect.  pytest's default `python_files`
  # is `test_*.py` and `*_test.py`; upstream's single test module is `test.py`,
  # which matches neither, because upstream drives it with nosetests — see the
  # `nosetests --with-coverage` line in tox.ini, and nose's own pattern, which
  # accepts a bare `test`.  A path given on the command line is collected
  # whatever its name, so this is one line rather than an
  # `--override-ini=python_files=...` that would also change what pytest picks
  # up elsewhere in the tree.
  #
  # Without it the phase collected zero items and exited 5, exactly as the
  # sdist did before this package moved to fetchFromGitHub — the second half of
  # the same bug, and invisible until the first half was fixed.
  # `enabledTestPaths` rather than a raw pytest flag because the hook expands it
  # as a glob and aborts if it matches nothing, which is the whole defence
  # against this recurring silently.
  enabledTestPaths = [ "test/test.py" ];

  # Three of the recovered tests assert that `pgtest.which("ping")` returns
  # exactly "/bin/ping".  There is no /bin/ping on NixOS and no `ping` on the
  # build PATH, so `which` reaches its last resort — shelling out to `locate` —
  # and dies with FileNotFoundError on that instead.  Putting iputils in the
  # check inputs does not help: the answer would then be a store path, which is
  # still not the string the test wants.  They are testing a helper against an
  # FHS layout, which is not a thing this build can have.
  disabledTestPaths = [
    "test/test.py::Test_which::test_unix_which_is_executable"
    "test/test.py::Test_which::test_unix_which_unicode"
    "test/test.py::Test_which::testunix_which_path_is_executable"
  ];

  pythonImportsCheck = [ "pgtest" ];

  meta = {
    description = "Creates a temporary, local PostgreSQL cluster for unit testing";
    homepage = "https://github.com/jamesnunn/pgtest";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
