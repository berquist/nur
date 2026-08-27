{
  lib,
  buildPythonPackage,
  fetchPypi,
  flit-core,
  click,
  lazy-model,
  pydantic,
  pymongo,
  typing-extensions,
}:

buildPythonPackage rec {
  pname = "beanie";
  version = "2.1.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-RPPFBxCqkNqpycQPm/nIlUlo/hbX5TmMHy/UYtr5T+E=";
  };

  build-system = [ flit-core ];

  dependencies = [
    click
    lazy-model
    pydantic
    pymongo
    typing-extensions
  ];

  # tests/conftest.py hard-codes mongodb_dsn = "mongodb://localhost:27017/…"
  # and every fixture under tests/odm connects to it, so the suite needs a live
  # mongod.  Standing one up in a build sandbox would make this package depend
  # on mongodb, which is SSPL — an unfree build input for an Apache-2.0 library.
  # The odm layer is exercised for real by the oasis-upload VM test instead.
  doCheck = false;

  pythonImportsCheck = [ "beanie" ];

  meta = {
    description = "Asynchronous Python ODM for MongoDB, built on pydantic";
    homepage = "https://github.com/BeanieODM/beanie";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
