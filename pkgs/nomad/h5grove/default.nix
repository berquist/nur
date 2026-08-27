{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  hatchling,
  h5py,
  numpy,
  orjson,
  tifffile,
  typing-extensions,
  # h5grove[fastapi] — the only backend NOMAD mounts
  fastapi,
  pydantic,
  pydantic-settings,
  uvicorn,
  # tests
  pytestCheckHook,
  httpx,
  pytest-benchmark,
}:

buildPythonPackage rec {
  pname = "h5grove";
  version = "4.0.0";
  pyproject = true;

  # From GitHub rather than the sdist: the sdist ships no tests, and the
  # backend tests are the only thing that exercises the HDF5 slicing NOMAD's
  # /h5grove endpoints depend on.
  src = fetchFromGitHub {
    owner = "silx-kit";
    repo = "h5grove";
    tag = "v${version}";
    hash = "sha256-Df7O3EFRsSz9Ur7hm+YNFEJ5dPoMyk1ItO31PV/odJA=";
  };

  build-system = [ hatchling ];

  dependencies = [
    h5py
    numpy
    orjson
    tifffile
    typing-extensions
    # the fastapi extra, which is what `h5grove[fastapi]` in nomad-lab asks for
    fastapi
    pydantic
    pydantic-settings
    uvicorn
  ];

  nativeCheckInputs = [
    pytestCheckHook
    httpx
    pytest-benchmark
  ];

  # Only the FastAPI backend and the shared utilities.  The flask and tornado
  # backends are alternative front ends that NOMAD never mounts, and running
  # them would pull flask, flask-compress, flask-cors, tornado and
  # pytest-tornado in as build inputs for no coverage of anything we ship.
  enabledTestPaths = [
    "src/tests/test_fastapi.py"
    "src/tests/test_utils.py"
  ];

  pythonImportsCheck = [
    "h5grove"
    "h5grove.fastapi_utils"
  ];

  meta = {
    description = "Core utilities to serve HDF5 file contents over HTTP";
    homepage = "https://github.com/silx-kit/h5grove";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.berquist ];
  };
}
