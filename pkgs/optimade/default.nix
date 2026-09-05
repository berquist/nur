{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  email-validator,
  lark,
  pydantic,
  pydantic-settings,
  pyyaml,
  requests,

  # tests
  pytestCheckHook,
  jsondiff,
}:

# optimade-python-tools, minus its FastAPI server half.  `emmet.core.optimade`
# imports `optimade.models` (the pydantic schemas for the OPTIMADE API); that is
# all this needs to satisfy, and it is what unblocks `emmet-core`'s
# `test_optimade.py`.  Package name is `optimade`, matching the distribution.
buildPythonPackage (finalAttrs: {
  pname = "optimade";
  version = "1.5.0";
  pyproject = true;
  __structuredAttrs = true;

  # The `providers/` submodule is left empty (fetchSubmodules unset): it holds
  # the provider list used by the server and validator tests, not by the models
  # this is packaged for.
  src = fetchFromGitHub {
    owner = "Materials-Consortia";
    repo = "optimade-python-tools";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/z7bUabsEJN91atDRRGqu/daapMEq6axM7AlQQIUSzQ=";
  };

  # Version is `dynamic`, read from `optimade.__version__` via
  # `[tool.setuptools.dynamic]`, so setuptools resolves it from the source with
  # no help needed.  `email-validator` covers the `pydantic[email]` extra —
  # `optimade.models.references` validates author addresses with `EmailStr`.
  build-system = [ setuptools ];

  # `ServerConfig.check_license_info` does an unconditional `requests.head` on
  # the license URL, and the shared test config sets `license = "CC-BY-4.0"`,
  # so five model tests that touch a `ServerConfig` fail on DNS.  Null it out —
  # the field is server metadata, unrelated to the models this is packaged for.
  postPatch = ''
    substituteInPlace tests/test_config.json \
      --replace-fail '"license": "CC-BY-4.0",' '"license": null,'
  '';

  dependencies = [
    email-validator
    lark
    pydantic
    pydantic-settings
    pyyaml
    requests
  ];

  # Only the parts that need neither the server extras (`optimade[server]` —
  # FastAPI, uvicorn) nor the empty `providers/` submodule.  `tests/models` is
  # what `emmet-core` depends on being correct; the filter and transformer
  # trees are pure-Python and come along for free.
  enabledTestPaths = [
    "tests/models"
    "tests/filterparser"
    "tests/filtertransformers"
  ];

  # `[tool.pytest.ini_options]` sets `filterwarnings = ["error", ...]`, which
  # turns any warning this repo's newer dependencies raise into a failure.
  pytestFlags = [ "--override-ini=filterwarnings=" ];

  nativeCheckInputs = [
    pytestCheckHook
    jsondiff
  ];

  pythonImportsCheck = [
    "optimade"
    "optimade.models"
  ];

  meta = {
    description = "Tools for implementing and consuming OPTIMADE APIs (models only, no server)";
    homepage = "https://github.com/Materials-Consortia/optimade-python-tools";
    changelog = "https://github.com/Materials-Consortia/optimade-python-tools/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
