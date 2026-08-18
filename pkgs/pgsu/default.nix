{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  click,
  psycopg,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  postgresqlTestHook,
}:

buildPythonPackage rec {
  pname = "pgsu";
  version = "0.3.0";
  pyproject = true;

  # As with ../kiwipy, the sdist carries no `tests/`.  It also carries no
  # setup.py, which is the more urgent half: the build failed outright with
  # "Cannot import 'flit_core.buildapi'" because the build-system below said
  # setuptools while upstream's pyproject.toml has always said flit_core.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "pgsu";
    tag = "v${version}";
    hash = "sha256-BdJVJPc7y61hGXDQe9ewXlGsYl+pa15xepqxpd+4sac=";
  };

  build-system = [ flit-core ];

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
    pgtest
    postgresql
    postgresqlTestHook
  ];

  # Upstream's addopts carry `--cov=pgsu`, and pytest-cov is not here.
  pytestFlags = [ "--override-ini=addopts=" ];

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
