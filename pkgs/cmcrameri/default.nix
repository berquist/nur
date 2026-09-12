{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  matplotlib,
  numpy,
  packaging,

  # tests
  pytestCheckHook,
}:

# cmcrameri — Fabio Crameri's perceptually uniform scientific colour maps,
# wrapped for matplotlib.  Here for `doped`, which uses them for its defect
# plots, and for nothing else.  Internal, not re-exported.
buildPythonPackage (finalAttrs: {
  pname = "cmcrameri";
  version = "1.10-unstable-2026-08-05";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD, three commits past v1.10 and all of them CI bumps.
  src = fetchFromGitHub {
    owner = "callumrollo";
    repo = "cmcrameri";
    rev = "78f02a088fa3c4fb4cb8aa92bd8e52389ab9d09a";
    hash = "sha256-il4fCgz8dFU0OZDOzjqjIu4nhIZtTyJSdyKci0w4ZrE=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # setuptools-scm has no repository to read here, and its failure mode is a
  # `0.1.dev1` version rather than an error — so the pin is not optional.  The
  # `-unstable-` suffix is not PEP 440, so only the part before the first dash
  # goes in; the same shape as ../sella and ../atomate2.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  dependencies = [
    matplotlib
    numpy
    packaging
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # The colour-map data is what this package is: sixty `.txt` files under
  # `cmcrameri/cmaps/`, pulled into the wheel by `include-package-data` and
  # MANIFEST.in's `graft cmcrameri`.  The suite checks that they are found at
  # all and that each one builds a matplotlib `Colormap`, which is exactly the
  # thing packaging could get wrong, so it is worth running.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "cmcrameri"
    "cmcrameri.cm"
  ];

  meta = {
    description = "Perceptually uniform scientific colour maps for matplotlib";
    homepage = "https://github.com/callumrollo/cmcrameri";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
