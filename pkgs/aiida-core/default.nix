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
  procps,
  bash,
  jq,
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
  # The other two storage.py rewrites, PostgresCluster._create and
  # PostgresCluster._close, are one race seen from its two ends.  pgtest finds a
  # free port by binding a socket, reading the number back and closing it again
  # — its own docstring warns that "another process will steal the port between
  # this function getting the port and your intended process using it" — and
  # with 128 workers starting clusters at once, two of them eventually get the
  # same number.  The loser's postmaster dies at startup:
  #
  #     LOG:  could not bind IPv4 address "127.0.0.1": Address already in use
  #     HINT: Is another postmaster already running on port 47967?
  #     FATAL:  could not create any TCP/IP sockets
  #
  # and, because the winner *is* listening there, pgtest's readiness probe
  # connects anyway and reports success.  That worker then spends the whole
  # session on its neighbour's cluster, which works — the databases are uuid4s
  # and the roles are per-worker, per the rewrite above — and every test passes.
  #
  # Which of the two symptoms you get depends on which worker finishes first,
  # and neither of them names a port.  If the loser finishes first, its
  # `pg_ctl stop` looks for a PID file its own cluster directory never had:
  #
  #     RuntimeError: b'pg_ctl: PID file ".../data/postmaster.pid" does not
  #     exist\nIs server running?\n'
  #
  # If the winner finishes first, it stops the postmaster out from under a
  # worker that is still using it, and that worker dies mid-test instead, in
  # whatever query it happened to be running:
  #
  #     FAILED tests/cmdline/commands/test_run.py::TestAutoGroups
  #       ::test_autogroup_filter_class - AssertionError:
  #       psycopg.errors.AdminShutdown: terminating connection due to
  #       administrator command
  #
  # PGTest accepts an explicit `port`, so `_create` hands each worker the one
  # derived from its own index and the race has nowhere left to happen.  A Nix
  # build gets a private network namespace containing nothing but loopback, so
  # 45000 + n cannot collide with anything outside the build either.
  #
  # `_close` keeps its tolerance as the backstop for the case the port pinning
  # does not cover: no xdist, so no worker index, so pgtest choosing for itself
  # again.  That first symptom comes from a session fixture, which surfaces as
  # an ERROR rather than a failure, and the --only-rerun patterns below cannot
  # reach it.  Suppressing it loses nothing — pgtest's own `except` clause
  # removes the temporary directory before re-raising.  The match is on the
  # message rather than on RuntimeError, so a cluster that fails to stop for any
  # other reason still fails the build.
  #
  # TestLaunchersDryRun is the third of these, and the one that does not involve
  # a server at all: the shared resource is the working directory.  A dry run
  # writes its submit script to `submit_test/<date>-<counter>` *relative to the
  # current directory*, and all 128 workers have the same one, /build/source.
  # The four tests in that class each clean up afterwards with
  #
  #     shutil.rmtree(os.path.join(os.getcwd(), CALC_JOB_DRY_RUN_BASE_PATH))
  #
  # which takes the whole tree, not the subfolder they made.  SubmitTestFolder
  # itself is race-safe — it mkdirs in a loop and retries on EEXIST — so the
  # directory really is created; a neighbour's teardown then removes it between
  # that mkdir and the write, and presubmit lands on:
  #
  #     FileNotFoundError: [Errno 2] No such file or directory:
  #       '/build/source/submit_test/20260819-00002/_aiidasubmit.sh'
  #
  # `monkeypatch.chdir(tmp_path)` in the fixture gives each test its own working
  # directory, so the rmtree can only reach what that test created.  Nothing in
  # the class asserts on the path: the one test that inspects the folder reads
  # the absolute path back out of `node.dry_run_info`.
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
  #
  # The next three hunks are all the bill for relaxing click's upper bound just
  # above, and are worth reading together: upstream's `<8.3` is not
  # bookkeeping, it is load-bearing, and lifting it costs twelve tests in three
  # unrelated-looking clusters.
  #
  # aiida/transports/cli.py is the library half, so it is patched rather than
  # worked around in the tests — anyone running this package against click 8.3
  # hits it, not just the suite.  Eight tests, all of
  # TestVerdiComputerConfigure plus one transport parametrization, die on a
  # single line there.
  #
  # The editor rewrites are the test half.  Four tests spell their editor as
  # `sleep 1 ; vim ...`, which worked
  # while click ran it through a shell; click 8.3 runs
  # `subprocess.Popen(shlex.split(editor) + [filename])` with no shell, so the
  # `;` becomes a literal argument and the whole line executes as `sleep`:
  #
  #     sleep: invalid option -- 'c'
  #     click.exceptions.ClickException: sleep 1 ; vim ...: Editing failed
  #
  # That is precisely what upstream's `<8.3` guards, so it is ours to fix.
  # Dropping the delay rather than restoring a shell keeps what the tests are
  # actually about — they assert on text a real vim edited.  The delay existed
  # for click's `require_save` check, which compares the file's mtime across
  # the edit and returns None when it has not moved; that only needs a whole
  # second on a filesystem with one-second mtime granularity, and the build
  # runs on tmpfs.  The sibling parametrizations that already spell the editor
  # as a bare `vim -cwq` pass here, which is the evidence that the mtime check
  # succeeds without the sleep.
  #
  # The /bin/bash rewrite is what stood between the engine suites and green
  # after `procps` fixed the scheduler.  Roughly fourteen tests run a real
  # calcjob whose *code* is the absolute path `/bin/bash`, and a Nix build
  # sandbox does not have one — it provides `/bin/sh` and nothing else.  The
  # failure is indirect enough to be worth spelling out: the submit script
  # itself runs fine, because schedulers/plugins/direct.py invokes it as
  # `bash <script>` and its `#!/bin/bash` shebang is never consulted.  Only the
  # line *inside* it, `'/bin/bash' < aiida.in > aiida.out`, fails, so the job
  # is reported as finished with an empty output file and the parser rejects
  # it:
  #
  #     ExitCode(status=320, message='The output file contains invalid output.')
  #
  # The sed matches the quoted form only, which is exactly the code path: the
  # shebang literals in tests/schedulers (`'#!/bin/bash'`) and the one
  # `/usr/bin/bash` have no quote before the slash, so they are left alone —
  # and they must be, since those tests assert on generated script *text* and
  # never execute anything.  Both .py and .sh are swept because the .sh files
  # under tests/engine/.../test_calc_job/ are pytest-regressions references for
  # scripts the .py files generate; rewriting one side only would break the
  # comparison.  The two substituteInPlace calls after it handle the other
  # half: those two tests write their own executable and then run it, so their
  # shebang is live rather than decorative.
  #
  # tests/ only, deliberately.  The same default sits in
  # src/aiida/tools/pytest_fixtures/orm.py, which is installed and used by
  # downstream plugins, so patching it would pin real users — who do have
  # /bin/bash — to whichever bash this build happened to use.  Exactly one call
  # site in the suite leans on that default rather than passing a path, and it
  # gets the argument spelled out instead; `rg "aiida_code_installed\(" tests |
  # rg -v filepath_executable` is the check that it is still only one.
  #
  # tests/cmdline/commands/test_code.py spells its editor the same broken way
  # in three places and is deliberately left alone: those tests supply every
  # option non-interactively, so click never launches the editor and the string
  # is never split.  They would start failing the moment one of them became
  # interactive, and this is the note that says why.
  #
  # The last hunk is not for this package's own suite at all — it is for the
  # plugins.  src/aiida/manage/tests/pytest_fixtures.py is the *deprecated*
  # fixture plugin, the one that prints "please use aiida.tools.pytest_fixtures
  # instead" on import, and its `aiida_profile_factory` hardcodes a
  # process_control block naming RabbitMQ on 127.0.0.1:5672.  Every plugin here
  # whose conftest still says `pytest_plugins =
  # ['aiida.manage.tests.pytest_fixtures']` therefore gets a profile that
  # *declares* a broker nothing is serving, and the whole point of taking
  # aiida-core from main is that this build sandbox could never host one.
  #
  # Declaring one is worse than declaring none.  Manager.create_runner asks for
  # a communicator inside a `try: ... except ConfigurationError: pass`, so a
  # profile with no process_control yields a runner with `communicator=None` and
  # every in-process test works — which is exactly how ../aiida-octopus, on the
  # modern plugin, runs a real calcjob here.  A profile that names RabbitMQ
  # instead gets as far as opening the socket and raises
  # AMQPConnectionError, which is not a ConfigurationError and so is not caught:
  #
  #     FAILED tests/calculations/test_orca.py::test_default
  #       - aiormq.exceptions.AMQPConnectionError: [Errno 111] Connect call failed
  #
  # Deleting the block gives the deprecated plugin the same default the
  # supported one has had since it replaced it — `broker_backend: str | None =
  # None` in tools/pytest_fixtures/configuration.py, which omits the key.  A
  # plugin test that genuinely needs a broker still fails, just with the
  # ConfigurationError that says so.
  #
  # This one patches an installed module rather than tests/, unlike the
  # /bin/bash rewrite above, and that is deliberate: the module only ever runs
  # under pytest, and the consumers being fixed are the six AiiDA plugins in
  # this repo, which are built from this same package set.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "'click>=8.1.0,<8.3'" "'click>=8.1.0'"

    substituteInPlace src/aiida/transports/cli.py \
      --replace-fail \
        "        user = ctx.params.get('user', None) or orm.User.collection.get_default()
            computer = ctx.params.get('computer', None)" \
        "        def resolved(name):
                # click 8.3 seeds ctx.params with an UNSET sentinel for options
                # it has not processed yet, where 8.2 left the key absent.  The
                # sentinel is truthy and is not None, so it defeats both the
                # 'or' fallback below and the 'is None' test, and surfaces as
                # AttributeError: 'Sentinel' object has no attribute 'pk'.
                value = ctx.params.get(name, None)
                return value if isinstance(value, orm.Entity) else None

            user = resolved('user') or orm.User.collection.get_default()
            computer = resolved('computer')"

    substituteInPlace src/aiida/cmdline/params/options/interactive.py \
      --replace-fail \
        "        try:
                return super().process_value(ctx, value)" \
        "        try:
                if self.required and value is None:
                    # The '!' above turns into None, and click 8.2 counted None
                    # as missing, so a required option re-prompted.  8.3's
                    # value_is_missing() answers True only for its new UNSET
                    # sentinel, and UNSET cannot be used here: click converts it
                    # back to None before the callback, which would break the
                    # non-required case that asserts on a literal 'None'.
                    raise click.MissingParameter(ctx=ctx, param=self)
                return super().process_value(ctx, value)"

    substituteInPlace tests/cmdline/commands/test_node.py \
      --replace-fail \
        "        assert result.output.strip() == '\n'.join(expected_projections)" \
        "        assert [line.strip() for line in result.output.strip().splitlines()] == expected_projections"

    find tests -type f \( -name '*.py' -o -name '*.sh' \) \
      -exec sed -i "s|'/bin/bash'|'${bash}/bin/bash'|g" {} + \
      -exec sed -i 's|"/bin/bash"|"${bash}/bin/bash"|g' {} +

    substituteInPlace tests/engine/daemon/test_worker.py \
      --replace-fail \
        "code = aiida_code_installed('add')" \
        "code = aiida_code_installed('add', filepath_executable='${bash}/bin/bash')"

    substituteInPlace tests/calculations/test_stash.py \
      --replace-fail "#!/bin/bash" "#!${bash}/bin/bash"

    substituteInPlace tests/orm/models/test_models.py \
      --replace-fail "#!/bin/bash" "#!${bash}/bin/bash"

    substituteInPlace tests/storage/psql_dos/test_backend.py \
      --replace-fail \
        "def test_get_info(monkeypatch):" \
        "def test_get_info(monkeypatch, aiida_profile_clean):"

    substituteInPlace tests/cmdline/utils/test_multiline.py \
      --replace-fail \
        "COMMAND = 'sleep 1 ; vim" \
        "COMMAND = 'vim"

    substituteInPlace tests/cmdline/commands/test_computer.py \
      --replace-fail \
        "os.environ['VISUAL'] = 'sleep 1; vim -cwq'
        os.environ['EDITOR'] = 'sleep 1; vim -cwq'" \
        "os.environ['VISUAL'] = 'vim -cwq'
        os.environ['EDITOR'] = 'vim -cwq'" \
      --replace-fail \
        "('sleep 1; vim -cwq',)" \
        "('vim -cwq',)"

    substituteInPlace tests/manage/configuration/test_profile.py \
      --replace-fail \
        "@pytest.mark.usefixtures('aiida_profile_clean')
    def profile_with_minimal_data():" \
        "def profile_with_minimal_data(aiida_profile_clean):" \
      --replace-fail \
        "@pytest.mark.usefixtures('aiida_profile_clean')
    def profile_with_actual_data(generate_calculation_node_io, generate_workchain_node_io):" \
        "def profile_with_actual_data(aiida_profile_clean, generate_calculation_node_io, generate_workchain_node_io):"

    substituteInPlace tests/engine/test_launch.py \
      --replace-fail \
        "    def init_profile(self, aiida_localhost):" \
        "    def init_profile(self, aiida_localhost, tmp_path, monkeypatch):" \
      --replace-fail \
        "        from aiida.common.folders import CALC_JOB_DRY_RUN_BASE_PATH" \
        "        from aiida.common.folders import CALC_JOB_DRY_RUN_BASE_PATH

            monkeypatch.chdir(tmp_path)"

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
        "'database_username': database_username or 'guest_' + os.environ.get('PYTEST_XDIST_WORKER', 'master')," \
      --replace-fail \
        "        try:
                self.cluster = PGTest()" \
        "        worker = os.environ.get('PYTEST_XDIST_WORKER', ''')
            port = 45000 + int(worker[2:]) if worker[:2] == 'gw' and worker[2:].isdigit() else None

            try:
                self.cluster = PGTest(port=port)" \
      --replace-fail \
        "    def _close(self):
            if self.cluster is not None:
                self.cluster.close()" \
        "    def _close(self):
            if self.cluster is not None:
                try:
                    self.cluster.close()
                except RuntimeError as exception:
                    if 'Is server running?' not in str(exception):
                        raise"

    # broker_virtual_host is an empty Python string upstream.  Two apostrophes
    # would close this whole block eleven hunks early, so it is written below
    # as three: that is how a Nix indented string escapes a literal pair.
    substituteInPlace src/aiida/manage/tests/pytest_fixtures.py \
      --replace-fail \
        "            'process_control': {
                    'backend': 'rabbitmq',
                    'config': {
                        'broker_protocol': 'amqp',
                        'broker_username': 'guest',
                        'broker_password': 'guest',
                        'broker_host': '127.0.0.1',
                        'broker_port': 5672,
                        'broker_virtual_host': ''',
                    },
                },
                'options': {" \
        "            'options': {"
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

    # tests/calculations/test_stash.py writes its own shell script as the code
    # for a StashCalculation and pipes the calculation's JSON through `jq` to
    # read source_path, source_list and target_base out of it, so the script
    # cannot work without it.
    #
    # It must be passed in explicitly by ../../overlays/default.nix, because
    # `jq` in a Python package set is the *binding*, python3.13-jq, which ships
    # no bin/jq.  Taking the defaulted argument put that in the closure and left
    # PATH exactly as it was.  See the callPackage site for the whole story.
    jq

    # `ps`, for the `core.direct` scheduler every calcjob test runs under.
    # aiida/schedulers/plugins/direct.py polls the job list with
    # `ps -xo pid,stat,user,time`, so without procps the scheduler never learns
    # that a job finished.  It fails quietly — the transport reports the
    # command's stderr as a *warning* and carries on with an empty job list:
    #
    #     Warning in _parse_joblist_output, non-empty (filtered)
    #     stderr='bash: line 1: ps: command not found
    #
    # What surfaces instead is a spray of unrelated-looking symptoms across the
    # engine suites: ExitCode(320) "The output file contains invalid output",
    # `assert False` on process states, and `verdi process kill` timing out
    # waiting for a state change that can never be observed.
    procps

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

    # Contention, not correctness.  With 128 xdist workers this build starts
    # 128 PostgreSQL clusters and a great many short-lived subprocesses, and a
    # handful of tests lose races that have nothing to do with what they test:
    # a cluster not up yet ("pg_ctl: PID file ... does not exist"), a
    # subprocess not yet reaped (psutil.ZombieProcess), a process that did not
    # reach its state inside a fixed timeout ("Process loading was too slow").
    # Which tests it hits varies run to run, which is what marks them as
    # scheduling artefacts rather than failures.
    #
    # The fourth is a data race inside plumpy rather than a timing margin, but
    # it behaves the same way and heals the same way.  Process.spec() builds the
    # spec on the class itself, in three steps that are not atomic:
    #
    #     cls._spec = cls._spec_class()
    #     cls.__called = False
    #     cls.define(cls._spec)          # sets cls.__called = True
    #     assert cls.__called, 'Process.define() was not called by ...'
    #
    # Two threads entering that block for the same class — the test's own and
    # the broker communicator's — can interleave so that the second resets
    # __called to False between the first's define() and its assert.  The
    # assertion message then names define(), which reads like a plugin that
    # forgot super().define(spec), and every AiiDA process class does call it.
    # A rerun is sound here because plumpy's own `except` clause deletes _spec
    # and clears __called before re-raising, so the retry rebuilds from scratch
    # rather than from the half-built state that failed.
    #
    # `--only-rerun` is why this is not a blanket retry: it takes a regex
    # matched against the *exception message*, so anything failing for any
    # other reason still fails on the first attempt.  Widening these patterns
    # would start hiding real bugs, so keep them specific.  pytest-rerunfailures
    # is already a nativeCheckInput because upstream declares it.
    #
    # No spaces in these patterns, and that is not a style choice.  Every entry
    # in `pytestFlags` reaches the hook through `concatTo`, which word-splits,
    # so an element containing a space arrives as several arguments — the `.`
    # wildcards below stand in for the spaces.  Spelling the middle one
    # "Process loading was too slow" silently turned `PID`, `file`, `loading`,
    # `was` and the rest into positional arguments, pytest read them as test
    # paths, and the whole run collected `0 items` and reported success at the
    # pytest level.  The `-k` expression a few lines up looks like a
    # counter-example but is not: pytestCheckHook builds that one into its bash
    # array itself, where the quoting survives.
    "--reruns"
    "2"
    "--only-rerun"
    "pg_ctl"
    "--only-rerun"
    "ZombieProcess"
    "--only-rerun"
    "Process.loading.was.too.slow"
    "--only-rerun"
    "Process.define...was.not.called"
  ]
  # The rest of the sshd story that disabledTestPaths below could not tell.
  # These four files each hold local-transport coverage worth keeping here, so
  # they cannot be relocated wholesale; only their SSH parametrizations move to
  # the `transports-ssh` VM test, which runs all four files unfiltered.
  #
  # tests/engine/daemon/test_execmanager.py drives every test through the
  # `node_and_calc_info` fixture, whose four params are (core.local, core.ssh,
  # core.ssh_async/asyncssh, core.ssh_async/openssh).  Only param 0 works
  # without a server, and the other three accounted for 108 of the 131 SSH
  # failures — 36 tests times three transports.  The params are tuples, so
  # pytest names them by index rather than by content; if upstream reorders or
  # adds one, the indices here shift silently.  The canary is the failure
  # count, since a wrongly-kept param fails loudly on connection refused.
  # The three params themselves are in `disabledTests` below rather than here:
  # pytestCheckHook builds one `-k` from that list *before* appending
  # pytestFlags, and pytest keeps only the last `-k` it is given, so a second
  # one here would silently discard every name in `disabledTests`.
  #
  # The remaining fifteen are enumerable, so they are deselected by exact node
  # id rather than by a `not ssh` name filter — that filter would also drop the
  # SSH tests that pass here precisely because they never open a connection.
  ++
    lib.concatMap
      (id: [
        "--deselect"
        id
      ])
      [
        "tests/engine/test_memory_leaks.py::test_leak_ssh_calcjob"
        "tests/tools/pytest_fixtures/test_orm.py::test_aiida_computer_fixtures[aiida_computer_ssh-BlockingTransport-core.ssh]"
        "tests/tools/pytest_fixtures/test_orm.py::test_aiida_computer_fixtures_async[asyncssh-_AsyncSSH]"
        "tests/orm/nodes/data/test_remote.py::test_clean[ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_du[ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_stat[ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_excs[ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup0-results0-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup1-results1-ssh]"
        # These two reported a fixture error rather than a connection failure
        # only because they lost a race for the `localhost` computer row first;
        # they are SSH-parametrized like the four above and belong in the VM.
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup2-results2-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup3-results3-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1-byte-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[10-bytes-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1000-bytes-ssh]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1e6-bytes-ssh]"

        # ------------------------------------------------------------------
        # Not an SSH matter, and not something a dependency can fix: these
        # thirteen assert byte counts that only hold on a filesystem which
        # allocates in 4096-byte blocks and does so immediately.
        #
        # `_get_size_on_disk_du` runs `du -s --block-size=1`, and upstream's
        # own comment above that call says the tests "assume a disk block size
        # of 4096 bytes", justified as "the default for Linux's ext4, as well
        # as macOS".  On ZFS — which is what this repo builds on — `du` charges
        # 1024 bytes per directory and *nothing at all* for file contents until
        # the transaction group commits some seconds later, so the numbers come
        # back constant regardless of what was written:
        #
        #     3 dirs + 3 files of 1 byte    got 3072, expected   24576
        #     3 dirs + 3 files of 1 MB      got 3072, expected 3022848
        #     2 dirs + 2 files of 1 MB      got 2048, expected 2015232
        #
        # btrfs delalloc gives the same shape.  Only the `du` assertions are
        # affected: test_get_size_on_disk_stat and _excs measure apparent size
        # and pass, which is why they are not listed.
        #
        # These stay enabled in the `transports-ssh` VM test, which runs this
        # file unfiltered on an ext4 root — the one place here where the
        # 4096-byte assumption actually holds.
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_du[local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup0-results0-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_params[setup1-results1-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1-byte-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[10-bytes-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1000-bytes-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_sizes[1e6-bytes-local]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[1-.-sizes0]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[100-.-sizes1]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[1000000-.-sizes2]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[1-subdir1-sizes3]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[100-subdir1-sizes4]"
        "tests/orm/nodes/data/test_remote.py::test_get_size_on_disk_nested[1000000-subdir1-sizes5]"

        # One more that needs a live sshd, missed when the SSH suites moved
        # because it fails on an *assertion* rather than on a connection error:
        # it expects "The provided remote absolute path ... does not exist on
        # the computer" and gets "Could not connect to the configured computer
        # to determine whether the specified executable exists."  It runs in
        # the VM alongside the others.
        "tests/orm/data/code/test_installed.py::test_validate_filepath_executable[core.ssh]"

        # Reaches the network, like the five names in `disabledTests`.  These
        # two are deselected by node id instead because the file's *other*
        # tests are local-only and worth keeping: both of these fetch a v0.4
        # archive from raw.githubusercontent.com, which the build sandbox
        # resolves to `FileNotFoundError: [Errno 2] ... 'https://raw.github...'`.
        "tests/cmdline/commands/test_archive_import.py::test_import_old_url_archives"
        "tests/cmdline/commands/test_archive_import.py::test_import_url_and_local_archives"

        # sphinx 9.1 against a reference built with sphinx 7.2.  This is the
        # gap the `sphinx` nativeCheckInput above warns about, and it has now
        # come due: the test is a pytest-regressions file comparison of
        # generated doctree XML, so any markup change upstream of it fails.
        # Nothing here is wrong with aiida; nixpkgs simply has no sphinx 7.
        "tests/sphinxext/test_workchain.py::test_workchain_build"

        # upf_to_json 1.0.0 emits a `label` ('5S', '5P', ...) on each chi entry
        # that the 0.9-era reference Ba.json shipped in aiida's test fixtures
        # does not carry, and the test's `compare` helper walks
        # `set(dd1) | set(dd2)` and indexes *both*, so the extra key is a
        # KeyError rather than a mismatch.  ../upf-to-json explains why 1.0.0
        # rather than the pinned 0.9.5 — 0.9.x ships no tests at all.
        "tests/orm/nodes/data/test_upf.py::TestUpfParser::test_upf2_to_json_barium"

        # pytz ships its own tz database, so this is a pytz-version difference
        # rather than a missing system one: the test hashes a datetime made
        # tz-aware with Europe/Amsterdam and compares against a literal digest.
        # The US/Eastern assertion two lines above it passes, which is what
        # rules out the hashing itself.
        "tests/common/test_hashing.py::TestMakeHashTest::test_datetime"

        # `verdi presto` autodetects a PostgreSQL server at 127.0.0.1:5432 and
        # /run/postgresql; pgtest gives each xdist worker a throwaway cluster on
        # a random port instead, so autodetection cannot succeed.  Supplying one
        # would mean a second, differently-configured server per worker.
        "tests/cmdline/commands/test_presto.py::test_presto_use_postgres"

        # `verdi process repair` counts connections to the profile's database
        # and, finding any it cannot attribute, asks for confirmation via
        # click.confirm(abort=True).  The pgtest cluster here always has one, so
        # the prompt fires, no input is supplied and the command aborts.  The
        # test is about `-v INFO` output and never meant to reach that branch;
        # passing --force instead is not an option, since it would terminate
        # the connection the test session itself is using.
        #
        # Four siblings share the cause: every test that invokes `verdi process
        # repair` expecting success, without --force and without feeding the
        # prompt.  Whether the prompt fires depends on what else is connected to
        # the worker's cluster at that instant, so they fail in different
        # combinations run to run — which is why this list grew after the first
        # one was deselected alone.  test_process_repair_dry_run and
        # _running_daemon are deliberately not here: --dry-run never reaches the
        # prompt, and _running_daemon expects a failure regardless.  The
        # connection-termination feature itself stays covered by
        # TestProcessRepairUnreferencedConnections, which drives the prompt on
        # purpose with user_input and --force.
        "tests/cmdline/commands/test_process.py::test_process_repair_verbosity"
        "tests/cmdline/commands/test_process.py::test_process_repair_consistent"
        "tests/cmdline/commands/test_process.py::test_process_repair_duplicate_tasks"
        "tests/cmdline/commands/test_process.py::test_process_repair_additional_tasks"
        "tests/cmdline/commands/test_process.py::test_process_repair_missing_tasks"

        # A consequence of the `--broker-backend zmq` chosen above.  The test
        # monkeypatches the runner's controller to None to reach the "runner
        # does not have a process controller" branch of aiida.engine.launch,
        # but with a zeromq profile an earlier guard fires first and raises
        # "Cannot submit because the daemon is not running.  The ZeroMQ broker
        # is bundled into the daemon for this profile" instead.  The test passes
        # under RabbitMQ, which the sandbox cannot supply.
        "tests/engine/test_launch.py::test_submit_no_broker"

        # The click 8.3 residue.  Both drive a command through a --config file
        # and end in `Aborted!` because an InteractiveOption prompts with no
        # input to consume.  Unlike the twelve fixed above, this one did not
        # reduce to a single line: --config is is_eager and click 8.3 keeps
        # 8.2's `(not is_eager, idx)` processing order, its consume_value still
        # honours default_map, and the config values do reach it — so the usual
        # suspects are ruled out and the actual trigger is still unidentified.
        # Worth revisiting whenever nixpkgs carries a click 8.2, which would
        # retire this whole family rather than these two.
        "tests/cmdline/commands/test_computer.py::TestVerdiComputerConfigure::test_local_from_config"
        "tests/cmdline/commands/test_setup.py::TestVerdiSetup::test_quicksetup_from_config_file"
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
    # Note how little of the *suite* this covers: the openssh nativeCheckInput
    # above is what fixed the bulk of the SSH failures, because most of them
    # never reached a connection.  Only what needs something listening is here.
    #
    # All three of these files are about the SSH transports end to end, so
    # moving them wholesale costs no coverage that stays behind — everything in
    # them runs in the VM, including the handful that would pass here.
    "tests/transports/test_all_plugins.py"
    "tests/transports/test_ssh.py"
    "tests/transports/test_asyncssh_plugin.py"
  ];

  disabledTests = [
    # Every one of these reaches a public structure database over the network:
    # COD, ICSD, Materials Project, MPDS, OQMD, TCOD.
    "test_dbimporters"
    "test_query"
    "test_cod"
    "test_icsd"
    "test_materialsproject"

    # The three SSH params of tests/engine/daemon/test_execmanager.py's
    # `node_and_calc_info` fixture — see the note in pytestFlags for why they
    # are named by index, and why they have to be expressed here rather than as
    # a `-k` of their own.
    "node_and_calc_info1"
    "node_and_calc_info2"
    "node_and_calc_info3"
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
