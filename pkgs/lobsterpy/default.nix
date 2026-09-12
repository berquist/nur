{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  numpy,
  pymatgen,

  # optional-dependencies
  mendeleev,

  # tests
  pytestCheckHook,
  pytest-mock,
}:

# Automated analysis of LOBSTER bonding outputs.  `emmet.core.lobster` imports
# it, and `emmet-core`'s `test_lobster.py` guards that import with
# `try / pytest.skip` — packaging it here turns the skip into real coverage.
# Also atomate2's `lobster` extra.
buildPythonPackage (finalAttrs: {
  pname = "lobsterpy";
  version = "0.6.1";
  pyproject = true;
  __structuredAttrs = true;

  # The v0.6.1 tag, not a later commit: `fa502f0` on master deletes the
  # `lobsterpy.cohp` module, and ../atomate2's `atomate2.lobster.schemas` still
  # imports `lobsterpy.cohp.analyze`.  v0.6.1 is the transitional release that
  # ships both `cohp` (for atomate2) and `coxx` (which ../emmet-core's
  # `emmet.core.lobster` uses) — the one version that satisfies both.
  src = fetchFromGitHub {
    owner = "JaGeo";
    repo = "LobsterPy";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hA/Gvv0xWwb6FKDjFKfn7KJ3fw7g0wKiuxwSrDceGz0=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository, the same
  # hole ../maggma falls into.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    numpy
    pymatgen
  ];

  # `mendeleev==1.2.0` — the pin matches what ../mendeleev carries, so no relax.
  optional-dependencies = {
    featurizer = [ mendeleev ];
  };

  # The featurizer extra is a check input because `tests/featurize/` exercises
  # `FeaturizeCharges`, which raises rather than skipping when mendeleev is
  # absent.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mock
  ]
  ++ finalAttrs.passthru.optional-dependencies.featurizer;

  pythonImportsCheck = [
    "lobsterpy"
    "lobsterpy.cohp.analyze" # atomate2 imports this
    "lobsterpy.coxx.analyze" # emmet-core imports this
    "lobsterpy.quality.analyze"
  ];

  meta = {
    description = "Automated analysis of LOBSTER bonding outputs";
    homepage = "https://github.com/JaGeo/LobsterPy";
    license = lib.licenses.bsd3;
    mainProgram = "lobsterpy";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
