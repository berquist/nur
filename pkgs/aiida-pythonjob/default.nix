{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  ase,
  node-graph,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  procps,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-pythonjob";
  version = "0.5.2-unstable-2026-07-20";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-pythonjob";
    rev = "fb8eb96454107c4d37f2c5a55cc7b99b0d793af2";
    hash = "sha256-YYnLVovsk8eGPi9D+eQWdMeJ89G4XiR7sr6h81Bf5tE=";
  };

  build-system = [ setuptools ];

  # See ../aiida-orca/default.nix for the pre-release reason.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    ase
    node-graph
  ];

  # `addopts = "--pdbcls=IPython.terminal.debugger:TerminalPdb"` in
  # pyproject.toml only selects which debugger `--pdb` would open, and `--pdb`
  # is never passed here — but pytest imports the class at startup regardless,
  # so the setting drags IPython into the check closure to choose a debugger
  # that can never be reached in a non-interactive run.  Dropping the line is
  # cheaper than carrying IPython, and changes nothing that runs.
  #
  # The broker is the same rewrite ../aiida-shell and ../aiida-workgraph need:
  # tests/conftest.py overrides aiida-core's `aiida_profile` to ask for
  # RabbitMQ, which a build sandbox cannot serve, and test_submit reaches it as
  #
  #   aiormq.exceptions.AMQPConnectionError: [Errno 111] Connect call failed
  #   ('127.0.0.1', 5672)
  #
  # `core.zeromq` runs inside the daemon and needs no service.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'addopts = "--pdbcls=IPython.terminal.debugger:TerminalPdb"' ""

    substituteInPlace tests/conftest.py \
      --replace-fail 'broker_backend="core.rabbitmq"' 'broker_backend="core.zeromq"'
  '';

  # `verdi` is aiida-core's console script, and aiida-core is propagated rather
  # than a build input, so its bin directory is not otherwise on the build
  # PATH.  tests/test_pythonjob.py::test_submit and
  # tests/test_async.py::test_async_function_kill start a daemon and stop at
  # "Unable to find 'verdi' in the path".  Same reasoning as
  # ../aiida-shell/default.nix.
  preCheck = ''
    export PATH="${aiida-core}/bin:$PATH"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # tests/conftest.py names the supported `aiida.tools.pytest_fixtures`,
    # whose profile is a real PostgreSQL one.  See ../pgtest for why postgresql
    # is listed alongside it.
    pgtest
    postgresql

    # A PythonJob *is* a calcjob, run through the `core.direct` scheduler,
    # which reads its joblist from `ps`.  Without it aiida retrieves before the
    # function has written its result, and thirty tests fail one step later —
    #
    #   output parser returned exit code<310>: The output file could not be read
    #   KeyError: 'result'
    #
    # with `ps: command not found` buried in the scheduler's stderr.  See
    # ../aiida-cp2k/default.nix.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  #
  # aiida_pythonjob/config.py runs `load_config()` at module scope, and that
  # calls aiida-core's `get_config()`, which raises rather than creating one:
  #
  #   aiida.common.exceptions.MissingConfigurationError: configuration file
  #   /build/tmp.../.aiida/config.json does not exist
  #
  # HOME and AIIDA_PATH are not enough on their own, because nothing in a build
  # ever runs `verdi`, which is what would normally create the file.  This is
  # pythonImportsCheckPhase failing, not a test — importing the package is
  # genuinely impossible without it.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
    python -c 'from aiida.manage.configuration import get_config; get_config(create=True)'
  '';

  pythonImportsCheck = [
    "aiida_pythonjob"
    "aiida_pythonjob.calculations"
    "aiida_pythonjob.data"
    "aiida_pythonjob.parsers"
  ];

  meta = {
    description = "AiiDA plugin that runs Python functions as calculations";
    homepage = "https://github.com/aiidateam/aiida-pythonjob";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
