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
  psutil,
  pytest-benchmark,
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
  nativeCheckInputs = [
    pytestCheckHook
    h5py
    numpy
    psutil
    pytest-benchmark
  ];

  # Upstream's addopts carries --cov-report --cov-append, which need pytest-cov
  # and write coverage output that is thrown away here.  Without either the
  # plugin or this, pytest does not merely skip them — it rejects the whole
  # invocation with "unrecognized arguments" before collecting anything.
  # Clearing the ini value is the same fix ../aiida-core uses, and for the same
  # reason.
  pytestFlags = [ "--override-ini=addopts=" ];

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
