{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  click,
  psycopg,

  # tests
  pytestCheckHook,
  postgresql,
  postgresqlTestHook,
}:

buildPythonPackage rec {
  pname = "pgsu";
  version = "0.3.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-Udu48ict6swo9UavRCoUEesmCx2lPhHU+T6pDysaz1A=";
  };

  build-system = [ setuptools ];

  # Upstream asks for `psycopg[binary]`, which on PyPI means a prebuilt wheel
  # bundling libpq.  The Nix equivalent is the `c` extra, which compiles the
  # same accelerated implementation against nixpkgs' own libpq.
  dependencies = [
    click
    psycopg
  ]
  ++ psycopg.optional-dependencies.c;

  # pgsu exists to *find* a way to connect to PostgreSQL as superuser, so its
  # tests are meaningless without a real cluster.  postgresqlTestHook starts one
  # over a Unix socket in $NIX_BUILD_TOP and exports PGHOST for it.
  nativeCheckInputs = [
    pytestCheckHook
    postgresql
    postgresqlTestHook
  ];

  # The hook's default PGUSER is an unprivileged `test_user`; pgsu needs the
  # superuser role that initdb created.
  env.PGUSER = "postgres";

  pythonImportsCheck = [ "pgsu" ];

  meta = {
    description = "Connect to an existing PostgreSQL cluster as a superuser";
    homepage = "https://github.com/aiidateam/pgsu";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
