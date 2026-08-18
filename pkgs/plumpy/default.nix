{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  greenback,
  greenlet,
  kiwipy,
  pyyaml,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  shortuuid,
}:

buildPythonPackage rec {
  pname = "plumpy";
  version = "0.26.0";
  pyproject = true;

  # `[tool.flit.sdist]` excludes `tests/`, as in ../kiwipy.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "plumpy";
    tag = "v${version}";
    hash = "sha256-dxd0gDe0pvte84U/gfSrp40fTvymzhPqNh8a2dsYpg4=";
  };

  build-system = [ flit-core ];

  dependencies = [
    greenback
    greenlet
    kiwipy
    pyyaml
  ]
  ++ kiwipy.optional-dependencies.rmq;

  # Upstream's `tests` extra also lists pytest-cov, which only the coverage
  # addopts below want.  pytest-notebook and ipykernel were never in it at all.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    shortuuid
  ];

  # `--cov-report xml --cov-append` without pytest-cov is an "unrecognized
  # arguments" abort, the same one ../disk-objectstore hit.
  pytestFlags = [ "--override-ini=addopts=" ];

  # The RabbitMQ-backed communicator tests need a live broker on localhost.
  # Everything else — the process state machine, which is what aiida-core
  # actually depends on — runs in-process and is exercised here.
  #
  # Note `tests/`, not `test/`: plumpy names the directory differently from
  # ../kiwipy, and a glob that matches nothing aborts the phase outright rather
  # than being ignored.
  disabledTestPaths = [ "tests/rmq" ];

  pythonImportsCheck = [
    "plumpy"
    "plumpy.processes"
  ];

  meta = {
    description = "A python workflow library, providing the process state machine used by AiiDA";
    homepage = "https://github.com/aiidateam/plumpy";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
