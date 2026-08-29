{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-pythonjob,
  aiida-shell,
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
  version = "0.8.1-unstable-2026-08-10";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-workgraph";
    rev = "5cccb31054974b4a364eedd44c26fc77c663a3fd";
    hash = "sha256-E4sLzdQCM9hK/LV6JRBCPVbDmxw3R7zs9XINbjdsKNU=";
  };

  build-system = [ flit-core ];

  # aiida-core for the usual pre-release reason, and aiida-shell because the
  # pin is `~=0.8` against the 0.9.0 in ../aiida-shell.  `node-graph~=0.6.5`
  # and `aiida-pythonjob~=0.5.2` are both satisfied by what this overlay
  # carries, so they are deliberately not in this list — a relax that is not
  # needed hides the day it becomes needed.
  pythonRelaxDeps = [
    "aiida-core"
    "aiida-shell"
  ];

  dependencies = [
    aiida-core
    aiida-pythonjob
    aiida-shell
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
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail "filepath_executable='/bin/bash'" "filepath_executable='${bash}/bin/bash'" \
      --replace-fail "filepath_executable='/bin/true'" "filepath_executable='${coreutils}/bin/true'" \
      --replace-fail "broker_backend='core.rabbitmq'" "broker_backend='core.zeromq'"

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
