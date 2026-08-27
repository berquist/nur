{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  lark,
  pydantic,
  pydantic-settings,
  requests,
  email-validator,
  # optimade[mongo] — what nomad-lab asks for
  mongomock,
  pymongo,
  # optimade[server] — nomad mounts the OPTIMADE app inside its own FastAPI app
  fastapi,
  pyyaml,
  starlette,
  uvicorn,
  # tests
  pytestCheckHook,
  pytest-asyncio,
  jsondiff,
}:

buildPythonPackage rec {
  pname = "optimade";
  version = "1.3.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-3LTlGGJMSc+v8c/8T4iZgA7KkXNuwZhYtgYn6W/azY0=";
  };

  build-system = [ setuptools ];

  dependencies = [
    lark
    pydantic
    pydantic-settings
    requests
    email-validator
    mongomock
    pymongo
    fastapi
    pyyaml
    starlette
    uvicorn
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    jsondiff
  ];

  # The suite runs against a mongomock-backed server, so it needs no live
  # MongoDB and no network.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "optimade"
    "optimade.server.config"
  ];

  meta = {
    description = "Reference server and models for the OPTIMADE materials API";
    homepage = "https://github.com/Materials-Consortia/optimade-python-tools";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.berquist ];
  };
}
