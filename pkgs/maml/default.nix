{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  numpy,
  setuptools,

  # dependencies
  matgl,
  mp-api,
  pymatgen,
  scikit-learn,
  scipy,

  # tests
  pytestCheckHook,
}:

# maml — MAterials Machine Learning, a library of ML models and descriptors for
# materials science.  One of matcalc's ML backends (`matcalc[maml]`).
buildPythonPackage {
  pname = "maml";
  version = "2025.4.3-unstable-2026-07-27";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialyzeai";
    repo = "maml";
    rev = "8916c6ea05ff19a1b351bd2b8f11e210750ba032";
    hash = "sha256-T96uyui/Q6najJUboLiirW76XpshaSa+O4LrqOSWim8=";
  };

  # `numpy` and `setuptools` are the build requirements — maml is pure Python
  # (`numpy` is a C-extension precaution upstream keeps); `version` is a plain
  # string in pyproject, so setuptools_scm is not involved.
  build-system = [
    numpy
    setuptools
  ];

  dependencies = [
    matgl
    mp-api
    numpy
    pymatgen
    scikit-learn
    scipy
  ];

  # Inherited from matgl, and it reaches this package through
  # `pythonImportsCheck` alone: `maml.describers` imports `maml.describers._matgl`,
  # which imports matgl, whose `config.py` runs
  # `MATGL_CACHE.mkdir(parents=True, exist_ok=True)` at module scope.
  # `MATGL_CACHE` is `~/.cache/matgl`, and the default `/homeless-shelter` is
  # not writable, so the import check fails with a `PermissionError` even though
  # `doCheck` is off.  Same one-line fix as ../matgl.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # The suite is not run.  The `apps/pes` tests wrap external fitting binaries
  # (`lmp`, `n2p2`, `mlp`), the DNN model tests need TensorFlow, and the
  # descriptor tests load matgl models over the network.  `pythonImportsCheck`
  # exercises the describer stack (matgl, torch).  The `symbolic` (cvxpy) and
  # `deep` (tensorflow) extras are declared for the same reasons.
  doCheck = false;

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "maml"
    "maml.base"
    "maml.describers"
  ];

  meta = {
    description = "Materials machine learning library";
    homepage = "https://github.com/materialyzeai/maml";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
