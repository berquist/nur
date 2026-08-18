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
  stdenv,
  pytestCheckHook,
  glibcLocalesUtf8,
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
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux glibcLocalesUtf8;

  # tests/conftest.py hardcodes `LOCALE = 'en_US.UTF-8'` and issues
  # `CREATE DATABASE ... LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8'`.  A nix
  # build sees only what glibc has built in — the cluster comes up saying "will
  # be initialized with locale 'C.UTF-8'" — so PostgreSQL rejected the statement
  # with "invalid LC_COLLATE locale name" and both tests that create a database
  # errored.
  #
  # Supplying the locale rather than rewriting the constant to C.UTF-8, because
  # a named non-C collation is part of what the statement is exercising, and
  # because the same rewrite would have to be undone on darwin, where en_US.UTF-8
  # is present and glibcLocalesUtf8 does not exist.  The UTF-8-only build is
  # enough here and is a fraction of the size of the full locale archive.
  #
  # It has to be exported rather than merely present: nixpkgs' glibc reads
  # LOCALE_ARCHIVE from the environment, and it is the postgres server started by
  # postgresqlTestHook, not pytest, that calls setlocale.  The server inherits
  # this from the build environment.
  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

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
