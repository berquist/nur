{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  click,
  sqlalchemy,

  # tests
  pytestCheckHook,
  h5py,
  numpy,
  openssh,
  psutil,
  pytest-benchmark,
  rsync,
  tqdm,
}:

buildPythonPackage rec {
  pname = "disk-objectstore";
  version = "1.5.0";
  pyproject = true;

  # fetchFromGitHub rather than fetchPypi, and this one is settled in the
  # metadata rather than merely observed: upstream's `[tool.flit.sdist]`
  # `exclude` lists `tests/` outright, so the sdist cannot run its own suite.
  # With fetchPypi the pytestCheckPhase collected nothing.  Same conclusion as
  # ../aiida-quantumespresso, and the same reason.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "disk-objectstore";
    tag = "v${version}";
    hash = "sha256-U6Kblh6bhgWSbFOx+dxISasZYMNfHiLNg/3L1jnS/NA=";
  };

  build-system = [ flit-core ];

  dependencies = [
    click
    sqlalchemy
  ];

  # psutil        tests/test_{container,utils}.py and the concurrent workers
  # pytest-benchmark  tests/test_benchmark.py, which uses the `benchmark` fixture
  # numpy         tests/test_optional.py, imported at module scope
  # h5py          the same file, but behind pytest.importorskip — included
  #               anyway, because the point of that file is to check the
  #               library against HDF5's whence=1/2 seeks, and skipping it
  #               silently would leave nothing testing that
  # tqdm          the `progressbar` extra.  `dostore validate --verbose` imports
  #               it inside the command and silently falls back to no progress
  #               bar when it is missing, so without it that whole branch of the
  #               command never runs during the check
  #
  # rsync and openssh are programs rather than modules, and BackupManager shells
  # out to both: it refuses to construct at all without rsync — "Input
  # validation failed: rsync not accessible" — which took out fourteen tests in
  # tests/test_backup.py that are about entirely different failure modes.
  # openssh is needed only by test_inaccessible_remote, which points a backup at
  # a random hostname and expects the ssh probe to fail; with no ssh binary at
  # all it fails the wrong way, with FileNotFoundError.
  nativeCheckInputs = [
    pytestCheckHook
    h5py
    numpy
    openssh
    psutil
    pytest-benchmark
    rsync
    tqdm
  ];

  # Upstream's addopts carries --cov-report --cov-append, which need pytest-cov
  # and write coverage output that is thrown away here.  Without either the
  # plugin or this, pytest does not merely skip them — it rejects the whole
  # invocation with "unrecognized arguments" before collecting anything.
  # Clearing the ini value is the same fix ../aiida-core uses, and for the same
  # reason.
  pytestFlags = [ "--override-ini=addopts=" ];

  # Three groups, none of which the inputs above can supply.
  #
  # click 8.2 gave CliRunner a separate stderr stream where 8.1 folded it into
  # stdout.  Four tests still assert against `result.stdout` for text that never
  # goes there: the "no `tqdm` package found" notice, which the CLI writes with
  # `err=True`; click's own usage error, which it also moved to stderr; and
  # tqdm's progress bar, which tqdm draws on stderr by default, so
  # test_validate[True] cannot see its "100%" however the package is built.  A
  # fifth expects a bare `dostore` to exit 0, where 8.2 exits 2.  All of them
  # are upstream tests that have not caught up, not defects in the library.
  #
  # The `remote` half of the backup tests points rsync at `localhost:<path>` and
  # needs a reachable sshd.  A build sandbox has no network and no daemon, so
  # these cannot pass here however much of openssh is present; the local half of
  # the same parametrisation covers the code that is not about transport.
  #
  # tests/test_examples.py runs the two scripts in disk_objectstore/examples as
  # subprocesses.  example_objectstore.py imports profilehooks at module scope,
  # which nixpkgs does not carry, so the whole file goes rather than half of it.
  # Reinstate it if profilehooks is ever packaged here.
  disabledTestPaths = [
    "tests/test_cli.py::test_main_command_missing_command"
    "tests/test_cli.py::test_main_command_no_params"
    "tests/test_cli.py::test_validate_no_progressbar"
    "tests/test_cli.py::test_validate[True]"
    "tests/test_cli.py::test_backup[True-None]"
    "tests/test_cli.py::test_backup_repeated[True]"
    "tests/test_examples.py"
  ];

  pythonImportsCheck = [
    "disk_objectstore"
    "disk_objectstore.container"
  ];

  meta = {
    description = "An implementation of an efficient object store writing loose objects and packs";
    homepage = "https://github.com/aiidateam/disk-objectstore";
    license = lib.licenses.mit;
    mainProgram = "dostore";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
