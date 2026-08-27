{
  lib,
  buildPythonPackage,
  fetchPypi,
  poetry-core,
  fastapi,
  pendulum,
  typing-extensions,
  uvicorn,
}:

buildPythonPackage rec {
  pname = "fastapi-cache2";
  version = "0.2.2";
  pyproject = true;

  src = fetchPypi {
    pname = "fastapi_cache2";
    inherit version;
    hash = "sha256-cb9EUBF9wkIk7BIL5Inb4J4zEUPJ9051629Xa3iSYCY=";
  };

  build-system = [ poetry-core ];

  # The redis / memcache / dynamodb backends are optional extras and NOMAD uses
  # only the in-memory one, so none of their clients are pulled in here.
  dependencies = [
    fastapi
    pendulum
    typing-extensions
    uvicorn
  ];

  # The sdist ships no tests; upstream's live in the repo and need a Redis and a
  # memcached instance for all but a handful of cases.
  pythonImportsCheck = [ "fastapi_cache" ];

  meta = {
    description = "Response cache for FastAPI, used by NOMAD's API layer";
    homepage = "https://github.com/long2ice/fastapi-cache";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
