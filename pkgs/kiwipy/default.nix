{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  flit-core,

  # dependencies
  deprecation,
  pyyaml,
  shortuuid,

  # optional-dependencies
  aio-pika,
  pamqp,
  pytray,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-notebook,
}:

buildPythonPackage rec {
  pname = "kiwipy";
  version = "0.9.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-PcWiy+S/cSfaLIpsIEdt2tMISbMvoStJXGIgWcYz208=";
  };

  build-system = [ flit-core ];

  dependencies = [
    deprecation
    pyyaml
    shortuuid
  ];

  # Not `rec`: the attribute names collide with the function arguments of the
  # same name, and under `rec` the attribute would win.  Same trap as
  # ../parsl/default.nix.
  optional-dependencies = {
    rmq = [
      aio-pika
      pamqp
      pytray
    ];
  };

  # aiida-core depends on `kiwipy[rmq]`, so the extra has to be installed
  # wherever kiwipy is, not merely declared.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-notebook
  ]
  ++ optional-dependencies.rmq;

  # Everything under test/rmq drives a real RabbitMQ broker on localhost, which
  # a build sandbox has no way to provide.  The rest of the suite is the
  # in-process communicator and the local event loop, and does run here.
  disabledTestPaths = [ "test/rmq" ];

  pythonImportsCheck = [
    "kiwipy"
    "kiwipy.rmq"
  ];

  meta = {
    description = "Robust, thread safe, message based communication";
    homepage = "https://github.com/aiidateam/kiwipy";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
