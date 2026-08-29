{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  dill,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
  bash,
  coreutils,
  diffutils,
  procps,
  unzip,
  which,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-shell";
  version = "0.9.0";
  pyproject = true;

  # Not fetchPypi: `[tool.flit.sdist] exclude` names `tests/`, so the sdist
  # carries no suite at all and the check phase would collect nothing and pass.
  # See the sdist-has-no-tests trap in ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-shell";
    tag = "v${version}";
    hash = "sha256-GUzKntcbsZsZH+BYrKZ/hyPwJGTMxaMI2Rj/O6fMH1k=";
  };

  build-system = [ flit-core ];

  # aiida-core here is 2.10.0.dev0, and a pre-release does not satisfy
  # `aiida-core~=2.6,>=2.6.1` under PEP 440 without an explicit opt-in.  See
  # ../aiida-orca/default.nix; every plugin in this repo needs this.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    dill
  ];

  # Five rewrites, and only the last is this package being unusual.
  #
  # The first four are absolute paths a Nix build sandbox does not have — it
  # provides /bin/sh and nothing else.  ../aiida-orca/default.nix has the long
  # form of why that surfaces as something other than "no such file": here the
  # `generate_code` fixture runs `which <command>` through the transport and
  # raises ValueError on a non-zero status, so `/bin/echo` fails as "failed to
  # determine the absolute path of the command".  `diff` is reached the same way
  # but by bare name, so it only needs diffutils on the check PATH — what has to
  # be rewritten is the *recorded* submit script it is compared against, which
  # carries the '/usr/bin/diff' the fixture was generated on.
  #
  # The fourth is a shebang rather than a lookup: test_metadata_computer builds
  # a PortableCode out of a script it writes itself, and the kernel is what
  # rejects it —
  #
  #   exit code 126: ./echo.sh: /bin/bash: bad interpreter: No such file or
  #   directory
  #
  # which the test sees only as `assert node.is_finished_ok` being False.  Note
  # the neighbouring `#!/bin/bash` in tests/calculations/test_shell/
  # test_filename_stdin.txt is deliberately left alone: that one is the *text*
  # of a submit script aiida generates and the test compares, never a file
  # anything executes.
  #
  # The fourth is the broker.  tests/conftest.py overrides aiida-core's own
  # `aiida_profile` fixture solely to ask for `broker_backend='core.rabbitmq'`,
  # because several tests submit to the daemon and a daemon needs a broker.  A
  # build sandbox can host neither RabbitMQ nor anything else listening on a
  # socket, which is exactly why aiida-core here comes from main: `core.zeromq`
  # runs inside the daemon as a circus watcher and needs no external service.
  # See ../aiida-core/default.nix (the `src` comment, and `--broker-backend` in
  # pytestFlags, which makes the same substitution for aiida-core's own suite).
  #
  # Note this is *not* the deprecated-fixture-plugin case that aiida-core
  # patches for aiida-orca and friends: this conftest names the supported
  # `aiida.tools.pytest_fixtures`, and asks for RabbitMQ in its own right.
  postPatch = ''
    substituteInPlace tests/test_launch.py \
      --replace-fail '#!/bin/bash\necho' '#!${bash}/bin/bash\necho'

    substituteInPlace tests/data/test_code.py \
      --replace-fail "/bin/bash" "${bash}/bin/bash"

    substituteInPlace tests/calculations/test_shell.py \
      --replace-fail "'/bin/echo'" "'${coreutils}/bin/echo'"

    substituteInPlace tests/calculations/test_shell/test_filename_stdin.txt \
      --replace-fail "'/usr/bin/diff'" "'${diffutils}/bin/diff'"

    substituteInPlace tests/conftest.py \
      --replace-fail "broker_backend='core.rabbitmq'" "broker_backend='core.zeromq'"
  '';

  # `verdi` is aiida-core's console script, and aiida-core is a *runtime*
  # dependency here — propagated, so its bin directory is not on the build
  # PATH.  The five tests that submit to the daemon need it: aiida starts the
  # daemon by running `verdi daemon start` and stops at
  #
  #   ConfigurationError: Unable to find 'verdi' in the path.
  #
  # before any of them reaches an assertion.  ../aiida-pseudo/default.nix does
  # the same thing with `$out/bin`, which works there because the executable is
  # that package's own.
  preCheck = ''
    export PATH="${aiida-core}/bin:$PATH"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.tools.pytest_fixtures`, whose profile is a
    # real PostgreSQL one; pgtest supplies a throwaway cluster.  See ../pgtest
    # for why postgresql has to be listed alongside it.
    pgtest
    postgresql

    # The commands the suite drives.  `which` is not incidental: the
    # `generate_code` fixture resolves every command through
    # `transport.exec_command_wait(f'which {command}')`, so without it every
    # test that builds a code node fails, including the ones that pass an
    # absolute path.  coreutils covers `true`, `date` and `echo`, diffutils the
    # `diff` of test_filename_stdin.
    coreutils
    diffutils
    which

    # test_nodes_remote_data builds a zip with shutil.make_archive and launches
    # `unzip` on it, which is neither in stdenv nor in coreutils.  `tar` and
    # `git`, which other tests name, are a different story: tar comes with
    # stdenv, and the `git diff` test never runs the program.
    unzip

    # The daemon tests submit through the `core.direct` scheduler, which reads
    # its joblist from `ps`.  ../aiida-cp2k/default.nix documents the shape that
    # failure takes when it is missing.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_shell"
    "aiida_shell.calculations"
    "aiida_shell.data"
    "aiida_shell.parsers"
  ];

  meta = {
    description = "AiiDA plugin that makes running shell commands easy";
    homepage = "https://github.com/aiidateam/aiida-shell";
    changelog = "https://github.com/aiidateam/aiida-shell/blob/master/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
