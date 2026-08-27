{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

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
}:

buildPythonPackage rec {
  pname = "kiwipy";
  version = "0.9.0";
  pyproject = true;

  # fetchFromGitHub rather than fetchPypi because upstream's
  # `[tool.flit.sdist]` exclude lists `test/` outright, so the sdist carries no
  # suite at all.  That is normally silent — pytestCheckPhase just collects
  # nothing — but here `disabledTestPaths` turned it into a hard error,
  # "Disabled tests path glob "test/rmq" does not match any paths".  Same as
  # ../qe-tools, ../disk-objectstore and ../archive-path.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "kiwipy";
    tag = "v${version}";
    hash = "sha256-CNe3Vec7vSzKyzM1zN1VjI9etsUlArs0AEmfHpvyNpU=";
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

  # The rmq extra is here because pythonImportsCheck imports `kiwipy.rmq`,
  # which needs aio_pika and pamqp present at check time.
  #
  # Upstream's `tests` extra also lists pytest-asyncio, pytest-notebook,
  # pytest-benchmark, pika, msgpack and ipykernel.  Every one of those belongs
  # to `test/rmq`, which is disabled below — the suite that does run here is
  # test/test_local.py and test/utils.py, and between them they import nothing
  # but pytest and kiwipy itself.
  nativeCheckInputs = [
    pytestCheckHook
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
