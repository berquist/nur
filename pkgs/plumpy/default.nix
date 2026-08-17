{
  lib,
  buildPythonPackage,
  fetchPypi,

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
  pytest-cov,
  pytest-notebook,
  ipykernel,
}:

buildPythonPackage rec {
  pname = "plumpy";
  version = "0.26.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-XQu0Q8OYP0MpW+UwauyX0J6ABaJ9HWRd6s8I2oSvtuE=";
  };

  build-system = [ flit-core ];

  dependencies = [
    greenback
    greenlet
    kiwipy
    pyyaml
  ]
  ++ kiwipy.optional-dependencies.rmq;

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-cov
    pytest-notebook
    ipykernel
  ];

  # The RabbitMQ-backed communicator tests need a live broker on localhost.
  # Everything else — the process state machine, which is what aiida-core
  # actually depends on — runs in-process and is exercised here.
  disabledTestPaths = [ "test/rmq" ];

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
