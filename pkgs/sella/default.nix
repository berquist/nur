{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  numpy,
  scipy,
  setuptools,
  setuptools-scm,

  # dependencies
  ase,
  jax,
  jaxlib,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "sella";
  version = "2.5.0-unstable-2026-07-13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zadorlab";
    repo = "sella";
    rev = "0e49415493b965536d1a061f892742d98b0e068d";
    hash = "sha256-e8Tto0uH3tNleTiuFnFDnTl8iPNaOu+zVp0VOu6lX9w=";
  };

  build-system = [
    cython
    numpy
    scipy
    setuptools
    setuptools-scm
  ];

  # setuptools-scm reads the version out of git, and fetchFromGitHub hands over
  # a tree with no .git.  Upstream configures `fallback_version = "0.0.0"`, so
  # without this the package installs as 0.0.0 *silently* rather than failing —
  # unlike ../basis-set-exchange, which has no fallback and dies outright.
  #
  # The `-unstable-` suffix has to come off first: setuptools-scm hands the
  # string to the packaging library, which rejects anything that is not PEP 440.
  # Deriving it from `version` rather than repeating "2.5.0" keeps the two from
  # drifting when this is next bumped.
  #
  # That leaves the installed metadata saying 2.5.0 while the derivation says
  # 2.5.0-unstable-2026-07-13, which is fine: mk-python-derivation.nix skips
  # pythonMetadataCheckPhase entirely for any version containing "unstable-".
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" version);

  # Two build-system caps are unmet here: `scipy >= 1.1.0, < 1.15` against
  # nixpkgs' 1.18, and `setuptools >= 74.1.0, < 82` against 83.0.0.
  #
  # **pythonRelaxDeps cannot do this.**  That hook rewrites the *runtime*
  # Requires-Dist of the built wheel; the check that fails here is the
  # build-dependency check, run against `[build-system] requires` before the
  # backend is even loaded:
  #
  #   ERROR Unmet dependencies (checked against .../bin/python3.13):
  #    scipy<1.15,>=1.1.0
  #               wanted: <1.15,>=1.1.0
  #            found: 1.18.0
  #
  # So the table has to be edited in the file.  Both caps are upstream being
  # cautious rather than known incompatibilities: setup.py imports numpy for its
  # include directory and never touches scipy, which is there for the Cython
  # sources' `scipy.linalg.cython_blas` / `cython_lapack` pxd files, and those
  # have been stable across the 1.1x series.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"setuptools >= 74.1.0, < 82",' '"setuptools >= 74.1.0",' \
      --replace-fail '"scipy >= 1.1.0, < 1.15",' '"scipy >= 1.1.0",'
  '';

  dependencies = [
    ase
    jax
    jaxlib
    numpy
    scipy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # testpaths = ["tests"] is already set in pyproject.toml.

  pythonImportsCheck = [
    "sella"
    # The three Cython extensions, imported explicitly: a build where cythonize
    # produced nothing still imports the pure-Python top level perfectly.
    "sella.force_match"
    "sella.utilities.blas"
    "sella.utilities.math"
  ];

  meta = {
    description = "Saddle point and minimum optimization for atomic systems";
    homepage = "https://github.com/zadorlab/sella";
    changelog = "https://github.com/zadorlab/sella/blob/master/CHANGELOG.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
