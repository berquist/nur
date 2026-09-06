{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  boto3,
  deltalake,
  emmet-core,
  monty,
  orjson,
  pyarrow,
  pymatgen,
  requests,
  typing-extensions,

  # tests
  pytestCheckHook,
}:

# mp-api — the REST client for the Materials Project.  Carried for
# `matcalc[maml]` (via ../maml) and atomate2's optional `mp` extra; also on the
# materials chain's own deferred list.  Distribution `mp-api`, import `mp_api`.
buildPythonPackage (finalAttrs: {
  pname = "mp-api";
  version = "0.46.5";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "api";
    tag = "v${finalAttrs.version}";
    hash = "sha256-p4nOLR0x8D74wkbUwwOEk/JAChm5Puge4w13o63BNUU=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  # `deltalake >= 1.4, < 1.6` — the client reads the MP parquet mirror through
  # it, an API stable across that range; relaxed so a channel a hair either side
  # still installs.
  pythonRelaxDeps = [ "deltalake" ];

  dependencies = [
    boto3
    deltalake
    emmet-core
    monty
    orjson
    pyarrow
    pymatgen
    requests
    typing-extensions
  ];

  # The suite is not run.  Every `tests/` module drives a live `MPRester`
  # against `api.materialsproject.org` and needs an API key — there is no
  # recorded-cassette layer.  Same shape as ../pubchempy.
  doCheck = false;

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "mp_api"
    "mp_api.client"
  ];

  meta = {
    description = "API client for the Materials Project";
    homepage = "https://github.com/materialsproject/api";
    changelog = "https://github.com/materialsproject/api/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.bsd3Lbnl;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
