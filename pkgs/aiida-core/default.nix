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
  sphinx,
  aiida-export-migration-tests,
  ipykernel,
  nbclient,
  nbformat,
  postgresql,
  openssh,
  which,
  rsync,
  vim,
  stdenv,
  glibcLocalesUtf8,
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

  # click is relaxed here rather than through pythonRelaxDeps below, because
  # pythonRelaxDepsHook cannot express it.  Its sed is unanchored —
  # `s/(Requires-Dist: $dep\s*…)[^;]*(;.*)?/\1\3/i` — so `click` matches the
  # *prefix* of the neighbouring `click-spinner~=0.1.8`, `[^;]*` eats the rest,
  # and the built METADATA comes out with two `Requires-Dist: click` lines and
  # no click-spinner requirement at all.
  #
  # That was harmless in practice, which is why it sat here unnoticed:
  # click-spinner is a dependency below regardless, and nixpkgs' 0.1.10 satisfies
  # `~=0.1.8` anyway, so nothing ever failed.  What it cost was the check — the
  # one requirement that stopped being verified was the one being clobbered.
  #
  # The entry could not simply be dropped: nixpkgs carries click 8.3.x and
  # upstream pins `<8.3`, so something has to give.  Patching the source is what
  # is exact, and --replace-fail makes it break loudly when upstream edits the
  # line rather than silently relaxing the wrong thing.
  # The storage.py rewrite at the end is what lets this suite run under xdist
  # at all.  aiida gives each test a database named after a fresh uuid4 but
  # leaves the *role* fixed — `database_username` defaults to 'guest' — and
  # creates it with a check-then-act:
  #
  #     if not postgres.dbuser_exists(...):
  #         postgres.create_dbuser(...)
  #
  # Workers interleave between those two lines and collide:
  #
  #     psycopg.errors.UniqueViolation: duplicate key value violates unique
  #     constraint "pg_authid_rolname_index"
  #     DETAIL:  Key (rolname)=(guest) already exists.
  #
  # 145 of those in one run and none in the next, both with 128 workers, which
  # is what makes it a race rather than a configuration error.  Appending
  # PYTEST_XDIST_WORKER gives each worker its own role and removes the shared
  # name the two lines disagree about; the databases were already unique.
  #
  # Turning parallelism off instead was tried and is not an option: nixpkgs'
  # pytest-xdist setup hook appends `--numprocesses=$NIX_BUILD_CORES` from
  # preInstallCheckHooks, after everything here, so a `-n 0` in pytestFlags is
  # silently overridden — only `dontUsePytestXdist` reaches it.  With that set
  # the suite ran serially and then *hung*: tests/engine/test_launch.py sat
  # until pytest-timeout's 240s fired and took the session down with it.
  #
  # This patches the installed library rather than the tests, so a plugin using
  # aiida.tools.pytest_fixtures gets the same fix — and, when not under xdist,
  # a role named guest_master rather than guest.  Both are throwaway clusters.
  #
  # The three fixture rewrites are a separate matter: a pytest 9
  # incompatibility, not a packaging choice.  Upstream pins `pytest~=7.0`; nixpkgs carries 9.1.1, which
  # turned "applying a mark to a fixture" from a deprecation warning into a
  # collection error:
  #
  #     ERROR tests/manage/configuration/test_profile.py
  #       - Failed: Marks cannot be applied to fixtures.
  #
  # Two whole modules failed to collect, and xdist reports a collection error
  # once per worker, so this showed up as 256 errors rather than as the two
  # problems it is.
  #
  # `@pytest.mark.usefixtures` on a fixture never had any effect pytest
  # guaranteed; requesting the fixture as an argument is the documented way to
  # say the same thing, and is what upstream will have to do. `aiida_profile_clean`
  # goes first in the signature so it still runs before the other fixtures.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "'click>=8.1.0,<8.3'" "'click>=8.1.0'"

    substituteInPlace tests/manage/configuration/test_profile.py \
      --replace-fail \
        "@pytest.mark.usefixtures('aiida_profile_clean')
    def profile_with_minimal_data():" \
        "def profile_with_minimal_data(aiida_profile_clean):" \
      --replace-fail \
        "@pytest.mark.usefixtures('aiida_profile_clean')
    def profile_with_actual_data(generate_calculation_node_io, generate_workchain_node_io):" \
        "def profile_with_actual_data(aiida_profile_clean, generate_calculation_node_io, generate_workchain_node_io):"

    substituteInPlace tests/orm/nodes/process/test_process.py \
      --replace-fail \
        "@pytest.mark.usefixtures('aiida_profile')
    def process_nodes():" \
        "def process_nodes(aiida_profile):"

    substituteInPlace src/aiida/tools/pytest_fixtures/storage.py \
      --replace-fail \
        "import pathlib
    import typing as t" \
        "import os
    import pathlib
    import typing as t" \
      --replace-fail \
        "'database_username': database_username or 'guest'," \
        "'database_username': database_username or 'guest_' + os.environ.get('PYTEST_XDIST_WORKER', 'master'),"
  '';

  # The locked nixpkgs sits above eight of upstream's upper bounds.  These are
  # metadata relaxations only: nothing here changes which version is installed,
  # it stops pythonRuntimeDepsCheckHook from refusing the ones nixpkgs has.
  #
  # pytz~=2021.1 against 2026.2 is the safe end of that: pytz is timezone data
  # with a stable API, and no distribution could still be shipping the 2021
  # release.  asyncssh~=2.22.0 against 2.24.0 is the one to watch — a tight pin
  # two minor versions behind, on the library AiiDA's SSH transport is built on.
  # The suite covers that transport, so a relaxation that does not hold should
  # surface as a test failure rather than at run time.
  #
  # **`upf_to_json` is spelled with an underscore on purpose.**  It was
  # `upf-to-json` here for months and relaxed nothing at all: pythonRelaxDepsHook
  # is a literal `sed -e "s/(Requires-Dist: $dep…)/…/i"`, case-insensitive but
  # with no PEP 503 name normalisation, and upstream's pyproject.toml writes
  # `upf_to_json~=0.9.2`.  A hyphen cannot match an underscore, so the
  # substitution never fired.
  #
  # Nothing says so when it happens.  An entry matching no Requires-Dist line is
  # a no-op, unlike a `disabledTestPaths` glob matching nothing, which aborts the
  # build — see the sdist-has-no-tests note in AGENTS.md for that half.  The
  # symptom is a failure naming a dependency you can see relaxed right here, and
  # pythonRuntimeDepsCheckHook normalises for its *error message*, so it reports
  # the very spelling that does not work.  Copy names from the project file
  # rather than from the error.
  #
  # upf_to_json is also the one entry that is not about nixpkgs being ahead.
  # The 0.9.x series ships no tests at all — so ../upf-to-json packages 1.0.0
  # instead, which does.  The call site here, src/aiida/orm/nodes/data/upf.py,
  # uses `upf_to_json(text, fname=...)`, and that signature is identical across
  # the two.
  pythonRelaxDeps = [
    "asyncssh"
    "importlib-metadata"
    "jedi"
    "paramiko"
    "pytz"
    "tabulate"
    "upf_to_json"
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

  # These two are preCheck rather than preBuild, unlike HOME above: nothing
  # before the check phase creates a database or starts a kernel, so there is
  # no earlier phase to cover.
  #
  # LOCALE_ARCHIVE is the same fix ../pgsu carries, for the same statement.
  # src/aiida/manage/external/postgres.py hardcodes
  #
  #     CREATE DATABASE "…" OWNER "…" ENCODING 'UTF8'
  #     LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0
  #
  # in `_CREATE_DB_COMMAND`, and a build sees only what glibc has built in, so
  # PostgreSQL rejects it with "invalid LC_COLLATE locale name".  Every test
  # that creates a profile hits it — 2657 failures in one run, which was very
  # nearly the whole suite.  It has to be exported rather than merely present,
  # because it is the postgres server that calls setlocale and it reads this
  # from the environment it inherited.
  #
  # JUPYTER_PATH is what makes `kernel_name='python3'` resolvable.  nixpkgs'
  # ipykernel installs its kernelspec to $out/share/jupyter/kernels/python3,
  # which is not under the interpreter's sys.prefix, so jupyter_client's search
  # path never reaches it — having ipykernel importable is not the same as
  # having the kernel registered.  JUPYTER_PATH takes priority over every other
  # location, and the spec's argv is a bare `python -m ipykernel_launcher`,
  # which resolves from the PATH and PYTHONPATH the check phase already has.
  # $out/bin is what puts `verdi` on the PATH, and 84 failures wanted it.
  # aiida.engine.daemon.client resolves the daemon command through
  # `shutil.which('verdi')` and raises ConfigurationError("Unable to find
  # 'verdi' in the path") when it cannot, which takes down every fixture that
  # starts a daemon — 256 of the 311 errors in one run were that one cause.
  # The check phase runs after installPhase, so $out is populated by now.
  preCheck = ''
    export PATH="$out/bin:$PATH"
    export JUPYTER_PATH="${ipykernel}/share/jupyter"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
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

    # Wanted twice over.  tests/sphinxext builds documentation through sphinx's
    # `app` fixture — that suite used to be in disabledTestPaths below purely
    # for want of this package, and is enabled again now that it is here.  And
    # tests/conftest.py sets
    # `pytest_plugins = ['aiida.tools.pytest_fixtures', 'sphinx.testing.fixtures']`
    # at the *suite root*, which pytest imports at collection startup, so
    # without sphinx the whole run dies before collecting a single test with
    # `Error importing plugin "sphinx.testing.fixtures": No module named
    # 'sphinx'` — deselecting the sphinx tests would not have helped.
    #
    # Upstream declares `sphinx~=7.2.0` in its `tests` extra; nixpkgs carries
    # 9.1.0.  `sphinx/testing/fixtures.py` still exists there, so the plugin
    # import is safe, but tests/sphinxext now runs against a sphinx seven minor
    # series newer than upstream tests against.  If it fails, that gap is the
    # first thing to look at.
    sphinx

    # tests/integration/notebook executes three real notebooks: it reads them
    # with nbformat and runs them through `nbclient.NotebookClient(...,
    # kernel_name='python3')`, which starts an actual kernel process.  All
    # three are in upstream's `tests` extra.  See preCheck for the kernelspec
    # half — the packages alone are not enough to make `python3` resolvable.
    ipykernel
    nbclient
    nbformat

    # pgtest shells out to initdb/pg_ctl/postgres from PATH; see ../pgtest.
    postgresql

    # The `ssh` and `scp` *clients*, which 78 failures wanted — far more than
    # the tests that need a server.  Much of tests/transports only builds a
    # command line, or probes for the binary, and fails on a bare
    # `FileNotFoundError: 'ssh'` long before any connection is attempted.  What
    # still needs a live sshd is in ../../tests/aiida/vm.nix.
    openssh

    # aiida.common.utils and several cmdline tests shell out to `which`.
    which

    # aiida.storage.psql_dos.backend's backup implementation resolves `rsync`
    # through is_exe_found() and refuses to start without it, so all eight
    # backup tests across tests/orm/implementation, tests/storage/psql_dos,
    # tests/storage/sqlite_dos and tests/cmdline/commands/test_storage.py fail
    # identically with "Input validation failed: rsync not accessible" — a
    # missing binary, not a backup bug.
    rsync

    # The editor the interactive cmdline tests drive.  `verdi computer setup`
    # and aiida.cmdline.utils.multi_line_input open $EDITOR through click, and
    # the tests parametrize over real vim command lines (`vim -cwq`, and one
    # that runs a `g!/^#=/s/$/Test` substitution), so a stub that only exits 0
    # would not do: they assert on the edited text coming back.
    vim

    # The archive fixtures tests/tools/archive/migration reads back, resolved
    # by importlib under a hyphenated name — see ../aiida-export-migration-tests.
    # Upstream pins it at ==0.9.0, which is also its newest tag.
    aiida-export-migration-tests
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux glibcLocalesUtf8
  ++ optional-dependencies.all;

  pytestFlags = [
    # Upstream's addopts carries --cov-report xml --cov-append --instafail,
    # which need pytest-cov and pytest-instafail and write coverage outside
    # $out.  Clearing the ini value is cleaner than installing both plugins
    # purely to satisfy flags whose output is thrown away.
    "--override-ini=addopts="

    # Restores what clearing addopts above took away.  It is dormant while
    # xdist is active — pytest-benchmark disables itself then, and says so —
    # which is exactly why it is easy to drop by accident: the moment anything
    # runs this suite without xdist, tests/benchmark's three modules stop being
    # skipped and start timing things in a build sandbox, where the numbers are
    # meaningless.  Keep it regardless of the worker count.
    "--benchmark-skip"

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
    # Not skipped — relocated.  These run in the `transports-ssh` VM test in
    # ../../tests/aiida/vm.nix, against a real sshd.
    #
    # The blocker is the account, not the daemon.  Nix's build sandbox writes
    # an /etc/passwd giving every user `/noshell`, on a read-only bind mount no
    # derivation can amend, and sshd execs the target user's login shell for
    # the commands AiiDA's transport runs.  An sshd here would accept the
    # connection and fail every command after it.
    #
    # Note how little this covers: the openssh nativeCheckInput above is what
    # fixed the bulk of the SSH failures, because most of them never reached a
    # connection.  Only what needs something listening is down here.
    "tests/transports/test_all_plugins.py"
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
