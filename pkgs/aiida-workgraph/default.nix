{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-pythonjob,
  cloudpickle,
  jsonschema,
  node-graph,
  node-graph-widget,
  numpy,
  scipy,

  # tests
  pytestCheckHook,
  pytest-xdist,
  pgtest,
  postgresql,
  bash,
  bc,
  coreutils,
  procps,
  which,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-workgraph";
  version = "1.0.0b4-unstable-2026-08-28";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-workgraph";
    rev = "502c1b5baaea252ff8b80d423f7f5f10e34ca315";
    hash = "sha256-oymqRxamABy6jOKKJ8pfZD5RVWtQCrVs4YwO2vBfs1s=";
  };

  # Two tests in tests/test_cli.py send a pause or a kill to a process that no
  # daemon worker has picked up yet, so the message goes nowhere:
  #
  #     ERROR aiida.process_control: Failed to kill Process<12>: Recipient not found: 12
  #
  # The `wg.wait(tasks={name: ['CREATED', 'RUNNING', 'WAITING']})` above each
  # of them looks like it guards against exactly that, and does not: it
  # compares against the WorkGraph *task* state, which has no WAITING member at
  # all and which the engine sets to RUNNING in the same breath as it calls
  # `submit()`.  So the wait returns the instant the calculation's node exists.
  # aiida-core logs the unroutable message rather than raising it, `result.
  # exit_code == 0` still holds, and the test then polls for twenty seconds for
  # a pause that was never requested.
  #
  # Whether the race is lost depends on machine load alone, which is why this
  # suite fails at `--numprocesses=32` and passes at 128: the busier the
  # builder, the further the test's own poll and its CliRunner startup -- both
  # CPU-bound -- slip behind the daemon's adoption of the process, which is an
  # idle event loop waking on a socket.  Nothing in the derivation differs
  # between the two runs.
  #
  # test_task_kill's `sqlite3.OperationalError: database is locked` is a
  # knock-on rather than a second defect, but not for the reason this note
  # used to give.  It said the pause test above aborts with its WorkGraph
  # still live in the daemon; the patch below makes that test pass, and the
  # lock survived it.  A pause test that *passes* also leaves its graph
  # running -- it returns the moment the task is unpaused -- and these
  # fixtures give each xdist worker one `core.sqlite_dos` profile and one
  # session-scoped daemon, so the next test on that worker writes to a single
  # sqlite file that a daemon worker is already writing to.
  #
  # What made that fatal was aiida-core's, and is fixed there: see the note
  # above `patches` in ../aiida-core/default.nix for the two SQLite defaults
  # and for why the failure lands twice, once as this lock and once as a
  # PendingRollbackError in whichever module the worker reached next.
  #
  # A patch file rather than `postPatch`: the insertion is multi-line Python at
  # a four-space indent, and Nix computes an indented string's dedent over the
  # whole literal -- see ../pymatgen/default.nix for what that quietly does to
  # a replacement that has to keep its indentation.  The header is written to
  # be sent upstream as-is.
  patches = [ ./await-daemon-adoption.patch ];

  build-system = [ flit-core ];

  # aiida-core for the usual pre-release reason.  `aiida-shell` used to be here
  # too, for a `~=0.8` pin against 0.9.0; the distribution is gone — aiida-core
  # absorbed it — and `pythonRemoveDeps` drops the requirement outright below.
  # `node-graph~=0.6.5` and `aiida-pythonjob~=0.5.2` are both satisfied by what
  # this overlay carries, so they are deliberately not in this list — a relax
  # that is not needed hides the day it becomes needed.
  pythonRelaxDeps = [ "aiida-core" ];

  # aiida-core vendored aiida-shell, so nothing provides this distribution any
  # more and the requirement cannot be satisfied at all.  Everything it named is
  # still here, under aiida's own namespace; see the import rewrites in
  # postPatch.
  pythonRemoveDeps = [ "aiida-shell" ];

  dependencies = [
    aiida-core
    aiida-pythonjob
    cloudpickle
    jsonschema
    node-graph
    node-graph-widget
    numpy
    scipy
  ];

  # Two absolute paths and the broker.
  #
  # /bin/bash and /bin/true are what the code fixtures install as executables,
  # and a build sandbox has only /bin/sh — see ../aiida-orca/default.nix.
  #
  # The broker is the same rewrite ../aiida-shell/default.nix needs, for the
  # same reason: tests/conftest.py overrides aiida-core's `aiida_profile` purely
  # to ask for `broker_backend='core.rabbitmq'`, because the engine tests submit
  # to a daemon.  `core.zeromq` runs inside the daemon as a circus watcher and
  # needs no service, which is why aiida-core here comes from main.
  #
  # The last two rewrites are the tests still failing once the broker was
  # sorted out, and they fail for opposite reasons.
  #
  # test_inputs_run_submit_api calls `wg.submit(..., wait=True)` without asking
  # for a daemon, while every other submitting test in that file carries
  # `@pytest.mark.usefixtures('started_daemon_client')`.  Under RabbitMQ that
  # oversight is invisible — an external broker accepts the submission — but
  # with the in-process ZeroMQ broker there is nothing to accept it, so the wait
  # runs to its 600-second limit.  Adding the fixture is what the rest of the
  # file already does.  Double quotes inside it, because the whole argument is
  # single-quoted for the shell.
  #
  # test_reset_message is deselected below rather than patched; see the note
  # above `disabledTestPaths`.
  #
  # The last rewrite is a timeout rather than a path.  aiida-core's
  # `daemon_client` fixture stops the daemon in its session teardown with
  # `stop_daemon(wait=True)`, and the circus call that makes is bounded by the
  # `daemon.timeout` config option, whose default is **two seconds**.  The
  # fixture catches only DaemonNotRunningException, so a slow quit is an error
  # rather than a warning, and it lands on whichever test happened to be last:
  #
  #     ERROR at teardown of test_organize_nested_inputs
  #     aiida.engine.daemon.client.DaemonTimeoutException: Connection to the daemon timed out.
  #
  # Two seconds is not a budget a builder running this suite 32 ways in
  # parallel can promise, the more so under `core.zeromq`, where the broker is
  # another circus watcher that `quit --waiting` has to bring down.  The same
  # option bounds the fixture's follow-up `_await_condition`, so raising it
  # once covers both halves of the teardown.
  #
  # It has to be set on the *profile*, not globally: `DaemonClient` reads it as
  # `config.get_option('daemon.timeout', scope=profile.name)`, and a scoped
  # read falls back to the option's own default rather than to the global
  # value, so a global `set_option` would be accepted and then ignored.
  # `aiida_config.store()` puts it on disk as well, for the
  # `verdi daemon start-circus` subprocess.  Thirty seconds rather than a
  # larger number: fifteen times the default is ample slack for a loaded
  # machine, while a daemon that is genuinely wedged still gives up inside the
  # build's patience.  `yield profile` occurs once in the file.
  postPatch = ''
    # kiwipy went the same way as plumpy — aiida-core absorbed it in 60aa10a4e
    # and no longer depends on it, so `import kiwipy` is a ModuleNotFoundError.
    # The one name used is the `Communicator` annotation on `message_receive`,
    # and aiida-core's own `message_receive` annotates it
    # `broker_communicator.Communicator` from aiida.brokers.communicator, which
    # is the same object under its new home.
    substituteInPlace src/aiida_workgraph/engine/workgraph.py \
      --replace-fail \
        'import kiwipy' \
        'from aiida.brokers import communicator as kiwipy_communicator' \
      --replace-fail 'kiwipy.Communicator' 'kiwipy_communicator.Communicator'

    # The next layer of the same drift: upstream deleted the `Protect`
    # metaclass from this module too, and replaced the two methods it guarded
    # -- `on_exiting`, `on_wait`, in that order -- with the standard library's
    # `typing.final`, a static-analysis-only marker with no runtime
    # enforcement.  `t.final` is that exact replacement, already reachable
    # under this module's own `import typing as t`.
    substituteInPlace src/aiida_workgraph/engine/workgraph.py \
      --replace-fail \
        'from aiida.engine.processes.workchains.workchain import Protect, WorkChainSpec' \
        'from aiida.engine.processes.workchains.workchain import WorkChainSpec' \
      --replace-fail 'class WorkGraphEngine(Process, metaclass=Protect):' 'class WorkGraphEngine(Process):' \
      --replace-fail '@Protect.final' '@t.final'

    # `ProfileParamType(load_profile=True)` is no longer a thing aiida-core
    # accepts: 9f3d98e45, "Load profile before verdi eager exits" (#7605), parses
    # the top-level verdi arguments up front and loads the profile there, so the
    # kwarg goes straight through to `object.__init__` and the CLI module dies at
    # import —
    #
    #   TypeError: object.__init__() takes exactly one argument (the instance to
    #   initialize)
    #
    # Dropping it gives up nothing: what it asked for is what upstream now does
    # unconditionally.  ../aiida-pseudo carries the same one line.
    substituteInPlace src/aiida_workgraph/cli/cmd_workgraph.py \
      --replace-fail \
        '@options.PROFILE(type=types.ProfileParamType(load_profile=True), expose_value=False)' \
        '@options.PROFILE(type=types.ProfileParamType(), expose_value=False)'

    # aiida-core vendored plumpy in 60aa10a4e and dropped the dependency; see
    # ../aiida-optimize for why the standalone library is not the answer.
    #
    # `Port` and `PortNamespace` map to the *generic* module, not to
    # aiida.engine.processes.ports — that one's PortNamespace is aiida's own
    # subclass, and plumpy's was the base these sockets are checked against.
    substituteInPlace src/aiida_workgraph/socket_spec.py \
      --replace-fail \
        'from plumpy.ports import Port, PortNamespace' \
        'from aiida.engine.processes.generic.ports import Port, PortNamespace'

    substituteInPlace src/aiida_workgraph/engine/workgraph.py \
      --replace-fail \
        'from plumpy import process_comms' \
        'from aiida.engine.processes import communications as process_comms' \
      --replace-fail \
        'from plumpy.persistence import auto_persist' \
        'from aiida.engine.processes.persistence import auto_persist' \
      --replace-fail \
        'from plumpy.process_states import Continue, Wait' \
        'from aiida.engine.processes.states import Continue, Wait' \
      --replace-fail \
        'from plumpy.workchains import _PropagateReturn' \
        'from aiida.engine.processes.workchains.outline import _PropagateReturn'

    # The third layer, and the one that cost ten tests rather than an import.
    # df3df5cc4, "Remove ineffective protected decorator" (#7607), renamed the
    # `Process` methods that were never public -- `set_logger`, `log_with_pid`,
    # `encode_input_args`, `decode_input_args` -- to carry a leading
    # underscore, "while preserving public APIs such as `out()` and
    # `load_instance_state()`".  aiida-core updated its own `WorkChain`, which
    # makes the identical call one line from this one; nothing updated the
    # plugins, and this is the only call site in the whole family
    # (`rg '\.set_logger\(' wc/ -g '*.py'` finds it and nothing else).
    #
    # What makes it expensive is *where* it sits: inside `load_instance_state`,
    # which is only ever reached when a process is recreated from its
    # checkpoint -- that is, by a daemon worker continuing a submitted process.
    # `wg.run()` builds the process in-process and never deserialises one, so
    # the whole suite looks healthy right up until something calls
    # `wg.submit()`, and then every such test fails at once:
    #
    #   11 failed, 230 passed -- and all eleven either submit, or assert on a
    #   task that a submitted graph was supposed to create.
    #
    # The AttributeError is raised inside the worker, so it excepts the process
    # rather than surfacing anywhere the test can see.  An EXCEPTED process is
    # terminal, which is why `wg.wait()` returns promptly instead of timing
    # out, and it has no report and no `exit_status`, which is why the failures
    # read as four unrelated complaints:
    #
    #   assert None == 5                      outputs never produced
    #   assert None == 302                    exit_status of an excepted process
    #   assert '...' in 'No log messages recorded for this entry'
    #   AttributeError: 'AiiDAFunctionTask' object has no attribute 'node'
    #
    # The last of those is not an API break, though it reads like one:
    # `Task.update_state` assigns `self.node` only when the task has a process
    # node, so a graph that never ran leaves the attribute unset.
    #
    # The four tests that instead time out -- test_task_pause_play,
    # test_task_kill, test_pause_play_task, test_task_monitor_kill -- are the
    # same defect seen from the other side: they wait for a *task* state that
    # only a running graph can reach.  Note that this puts the `--numprocesses`
    # note above out of date as an explanation of the current failures; the two
    # CLI tests it describes are a genuine race, but they cannot even be
    # reached while this is broken.
    substituteInPlace src/aiida_workgraph/engine/workgraph.py \
      --replace-fail \
        'self.set_logger(self.node._logger_adapter)' \
        'self._set_logger(self.node._logger_adapter)'

    substituteInPlace src/aiida_workgraph/utils/__init__.py \
      --replace-fail \
        'from plumpy.utils import AttributesFrozendict' \
        'from aiida.common.extendeddicts import AttributesFrozendict'

    substituteInPlace tests/test_engine.py \
      --replace-fail \
        'from plumpy.process_comms import MessageBuilder' \
        'from aiida.engine.processes.communications import MessageBuilder'

    # aiida-shell is not a distribution any more: aiida-core absorbed it in the
    # same release that absorbed plumpy, and this repo dropped the package
    # rather than ship a second copy of entry points aiida-core now registers
    # itself — two `core.shell` registrations is a MultipleEntryPointError at
    # import, not a subtle problem.  Every name moves to aiida's own namespace
    # and nothing else about them changed:
    #
    #   aiida_shell.ShellJob                      aiida.calculations.shell
    #   aiida_shell.calculations.shell.ShellJob   aiida.calculations.shell
    #   aiida_shell.launch.prepare_shell_job_inputs   aiida.tools.shell
    #   aiida_shell.launch.prepare_code           aiida.tools.shell
    #   aiida_shell.parsers.shell.ShellParser     aiida.parsers.plugins.shell.parser
    substituteInPlace src/aiida_workgraph/utils/__init__.py \
      --replace-fail \
        'from aiida_shell.calculations.shell import ShellJob' \
        'from aiida.calculations.shell import ShellJob'

    substituteInPlace src/aiida_workgraph/tasks/shelljob_task.py \
      --replace-fail \
        'from aiida_shell import ShellJob' \
        'from aiida.calculations.shell import ShellJob' \
      --replace-fail \
        'from aiida_shell.launch import prepare_shell_job_inputs' \
        'from aiida.tools.shell import prepare_shell_job_inputs' \
      --replace-fail \
        'from aiida_shell.parsers.shell import ShellParser' \
        'from aiida.parsers.plugins.shell.parser import ShellParser'

    substituteInPlace tests/test_shell.py \
      --replace-fail \
        'from aiida_shell.launch import prepare_code' \
        'from aiida.tools.shell import prepare_code'

    substituteInPlace tests/conftest.py \
      --replace-fail "filepath_executable='/bin/bash'" "filepath_executable='${bash}/bin/bash'" \
      --replace-fail "filepath_executable='/bin/true'" "filepath_executable='${coreutils}/bin/true'" \
      --replace-fail "broker_backend='core.rabbitmq'" "broker_backend='core.zeromq'" \
      --replace-fail 'yield profile' "profile.set_option('daemon.timeout', 30); aiida_config.store(); yield profile"

    substituteInPlace tests/test_workgraph.py \
      --replace-fail \
        'def test_inputs_run_submit_api():' \
        '@pytest.mark.usefixtures("started_daemon_client")
    def test_inputs_run_submit_api():'
  '';

  # One test waits for a state it will never catch.  test_reset_message polls
  # once a second for task `add1` to be in exactly `['RUNNING']`:
  #
  #   wg.wait(tasks={'add1': ['RUNNING']}, timeout=timeout, interval=1)
  #
  # It was first given a longer timeout, on the theory that a loaded builder was
  # simply slow.  That was wrong — 30 seconds and 180 seconds fail identically —
  # and the neighbouring tests say why: every other calcjob wait in this suite
  # accepts a *set* of states, `['CREATED']` in test_action.py or
  # `['CREATED', 'RUNNING', 'WAITING']` in test_cli.py, and those pass.  The
  # only other bare `['RUNNING']` wait, in test_monitor.py, watches a monitor
  # task, which stays running by design.  A calcjob task here evidently does not
  # sit in RUNNING long enough for a one-second poll to catch it, so no timeout
  # rescues this one; it is upstream's to fix.
  disabledTestPaths = [ "tests/test_workgraph.py::test_reset_message" ];

  # `verdi` is aiida-core's console script and aiida-core is a propagated
  # dependency, so its bin directory is not otherwise on the build PATH; the
  # tests that start a daemon stop at "Unable to find 'verdi' in the path".
  # Same reasoning as ../aiida-shell/default.nix.
  preCheck = ''
    export PATH="${aiida-core}/bin:$PATH"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # The `tests` extra asks for xdist, and at 199 tests across 42 modules this
    # suite is the one place in this family where it earns its keep.
    pytest-xdist

    # conftest.py names the supported `aiida.tools.pytest_fixtures`; see
    # ../pgtest for why postgresql accompanies pgtest.
    pgtest
    postgresql

    # The engine tests submit through the `core.direct` scheduler, which reads
    # its joblist from `ps`.  ../aiida-cp2k/default.nix has the shape of that
    # failure.
    procps

    # tests/test_shell.py drives aiida-shell's ShellJob, which resolves every
    # command through `which` on the computer before it will build a code —
    # without it the tests fail as "failed to determine the absolute path of
    # the command on the computer", the same way ../aiida-shell's own do.  The
    # commands themselves are `cat`, `echo` and `bc`.
    coreutils
    which
    bc
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  #
  # aiida-pythonjob's config.py runs `load_config()` at module scope, and that
  # calls aiida-core's `get_config()`, which raises rather than creating one:
  #
  #   aiida.common.exceptions.MissingConfigurationError: configuration file
  #   /build/tmp.../.aiida/config.json does not exist
  #
  # HOME and AIIDA_PATH are not enough on their own, because nothing in a build
  # ever runs `verdi`, which is what would normally create the file.  This package imports
  # aiida_pythonjob, so it inherits the requirement.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
    python -c 'from aiida.manage.configuration import get_config; get_config(create=True)'
  '';

  pythonImportsCheck = [
    "aiida_workgraph"
    "aiida_workgraph.engine"
    "aiida_workgraph.orm"
    "aiida_workgraph.tasks"
  ];

  meta = {
    description = "Designing and managing flexible workflows with AiiDA";
    homepage = "https://github.com/aiidateam/aiida-workgraph";
    license = lib.licenses.mit;
    mainProgram = "workgraph";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
