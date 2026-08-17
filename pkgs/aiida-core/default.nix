{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  alembic,
  archive-path,
  asyncssh,
  circus,
  click,
  click-spinner,
  disk-objectstore,
  docstring-parser,
  graphviz,
  importlib-metadata,
  ipython,
  jedi,
  jinja2,
  kiwipy,
  numpy,
  paramiko,
  pgsu,
  plumpy,
  psutil,
  psycopg,
  pydantic,
  pytz,
  pyyaml,
  requests,
  sqlalchemy,
  tabulate,
  tqdm,
  typing-extensions,
  upf-to-json,
  wrapt,

  # optional-dependencies
  ase,
  flask,
  flask-cors,
  flask-restful,
  matplotlib,
  pycifrw,
  pymatgen,
  pymysql,
  pyparsing,
  python-memcached,
  seekpath,
  spglib,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-benchmark,
  pytest-regressions,
  pytest-rerunfailures,
  pytest-timeout,
  pytest-xdist,
  pg8000,
  pgtest,
  pympler,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-core";
  version = "2.10.0.dev0-unstable-2026-08-16";
  pyproject = true;

  # Not fetchPypi.  The newest release is 2.9.0, and the ZeroMQ broker —
  # src/aiida/brokers/zeromq/, entry point `core.zeromq` — exists only on main.
  # That broker runs inside the daemon as a circus watcher and needs no external
  # service at all, which is what lets ../../nixos-modules/aiida.nix default to
  # a deployment with nothing but PostgreSQL behind it, and what lets the tests
  # below run in a sandbox that could never host RabbitMQ.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-core";
    rev = "e56a90689325d5296add6565fbff1b9e38789ac5";
    hash = "sha256-8zuLtmE/IkYoZSd3Sqm+ZptpMrUq/Ek1ooHuufz+Vbw=";
  };

  build-system = [ flit-core ];

  # The locked nixpkgs sits above six of upstream's upper bounds.  These are
  # metadata relaxations only: nothing here changes which version is installed,
  # it stops pythonRuntimeDepsCheckHook from refusing the ones nixpkgs has.
  #
  # upf-to-json is the one that is not about nixpkgs.  Upstream asks for
  # `upf_to_json~=0.9.2`, and the 0.9.x series ships no tests at all — so
  # ../upf-to-json packages 1.0.0 instead, which does.  The call site here,
  # src/aiida/orm/nodes/data/upf.py, uses `upf_to_json(text, fname=...)`, and
  # that signature is identical across the two.
  pythonRelaxDeps = [
    "click"
    "importlib-metadata"
    "jedi"
    "paramiko"
    "tabulate"
    "upf-to-json"
    "wrapt"
  ];

  dependencies = [
    alembic
    archive-path
    asyncssh
    circus
    click
    click-spinner
    disk-objectstore
    docstring-parser
    graphviz
    importlib-metadata
    ipython
    jedi
    jinja2
    kiwipy
    numpy
    paramiko
    pgsu
    plumpy
    psutil
    psycopg
    pydantic
    pytz
    pyyaml
    requests
    sqlalchemy
    tabulate
    tqdm
    typing-extensions
    upf-to-json
    wrapt
  ]
  # aiida-core asks for `kiwipy[rmq]` and `psycopg[binary]`, not the bare
  # distributions.  The rmq extra is what supplies the RabbitMQ broker backend;
  # the ZeroMQ one is built in.  psycopg's `binary` extra is a prebuilt wheel on
  # PyPI, and `c` is nixpkgs' equivalent — the same accelerated implementation,
  # compiled against nixpkgs' libpq.
  ++ kiwipy.optional-dependencies.rmq
  ++ psycopg.optional-dependencies.c;

  # Not `rec`: attribute names like `ase` and `flask` collide with the function
  # arguments of the same name, and under `rec` the attribute wins, giving a
  # list that contains itself.  Same trap as ../parsl/default.nix.
  #
  # `atomic_tools` is not a convenience here: aiida-quantumespresso depends on
  # `aiida_core[atomic_tools]`, so the extra has to exist for that package's
  # runtime dependency check to pass.
  #
  # Extras deliberately omitted: `tui` (trogon is not in nixpkgs), `bpython`,
  # `notebook`, `docs`, `pre-commit`, `ssh_kerberos`.
  optional-dependencies =
    let
      extras = {
        atomic_tools = [
          ase
          matplotlib
          pycifrw
          pymatgen
          pymysql
          seekpath
          spglib
        ];
        rest = [
          flask
          flask-cors
          flask-restful
          pyparsing
          python-memcached
          seekpath
        ];
      };
    in
    extras // { all = lib.concatLists (lib.attrValues extras); };

  # aiida.manage.configuration.settings runs AiiDAConfigDir.set() at *module
  # import*, which creates $HOME/.aiida (and warns that it did).  The default
  # /homeless-shelter does not exist, so anything importing aiida fails there —
  # that is pythonImportsCheck as well as the test suite, and those run in
  # different phases.  genericBuild runs every phase in one shell, so exporting
  # this once, early, covers all of them.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-benchmark
    pytest-regressions
    pytest-rerunfailures
    pytest-timeout
    pytest-xdist
    pg8000
    pgtest
    pympler

    # pgtest shells out to initdb/pg_ctl/postgres from PATH; see ../pgtest.
    postgresql
  ]
  ++ optional-dependencies.all;

  pytestFlags = [
    # Upstream's addopts carries --cov-report xml --cov-append --instafail,
    # which need pytest-cov and pytest-instafail and write coverage outside
    # $out.  Clearing the ini value is cleaner than installing both plugins
    # purely to satisfy flags whose output is thrown away.
    "--override-ini=addopts="

    # tests/conftest.py defaults to `sqlite` storage and the `rmq` broker.
    # RabbitMQ is the one dependency a build sandbox cannot supply, and psql is
    # the backend the NixOS module actually deploys — so run the combination
    # that is both testable here and representative: a throwaway PostgreSQL
    # cluster from pgtest, and the in-process ZeroMQ broker.
    "--db-backend"
    "psql"
    "--broker-backend"
    "zmq"
  ];

  disabledTestPaths = [
    # Needs aiida-export-migration-tests, which pins an exact version and is
    # not in nixpkgs.  The migration logic it covers is upstream's own archive
    # history, not anything this packaging can break.
    "tests/tools/archive/migration"

    # Drives a live sshd on localhost with passwordless key auth, which the
    # sandbox has no way to provide.  The local transport is covered.
    "tests/transports/test_all_plugins.py"

    # Builds documentation through the sphinx `app` fixture.
    "tests/sphinxext"
  ];

  disabledTests = [
    # Every one of these reaches a public structure database over the network:
    # COD, ICSD, Materials Project, MPDS, OQMD, TCOD.
    "test_dbimporters"
    "test_query"
    "test_cod"
    "test_icsd"
    "test_materialsproject"
  ];

  pythonImportsCheck = [
    "aiida"
    "aiida.engine"
    "aiida.orm"
    "aiida.storage.psql_dos"
    "aiida.brokers.zeromq"
  ];

  meta = {
    description = "Workflow manager for computational science with a focus on provenance";
    homepage = "https://github.com/aiidateam/aiida-core";
    changelog = "https://github.com/aiidateam/aiida-core/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    # The console scripts are `verdi` and `runaiida`; neither is named after the
    # package.  Without this, lib.getExe — which ../../nixos-modules/aiida.nix
    # and every consumer reach for — silently resolves to $out/bin/aiida-core,
    # which does not exist.
    mainProgram = "verdi";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
