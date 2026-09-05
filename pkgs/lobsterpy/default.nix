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
  version = "0.6.1-unstable-2026-08-05";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v0.6.1 tag, which is 29 behind it: the interim
  # commits drop the deprecated `cohp` module and adapt the code and tests to
  # newer pymatgen, which is the pairing this repo has.
  src = fetchFromGitHub {
    owner = "JaGeo";
    repo = "LobsterPy";
    rev = "cb39f3a129ac1016beb6947c5b316de87a88d644";
    hash = "sha256-AcGQg45B3wKrmiZUdbflC5BqqXbu8vu7pm1JGSuPTmU=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository, the same
  # hole ../maggma falls into.  The `-unstable-` suffix is not PEP 440, so only
  # the part before the first dash goes in.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

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
    "lobsterpy.coxx.analyze"
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
