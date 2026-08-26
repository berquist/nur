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

  # `import sella` sets up a JAX persistent compilation cache at module scope —
  # sella/__init__.py line 11, before anything else runs:
  #
  #   _cache_dir = os.environ.setdefault("JAX_COMPILATION_CACHE_DIR",
  #                                      os.path.expanduser("~/.cache/sella/jax_cache"))
  #   os.makedirs(_cache_dir, exist_ok=True)
  #
  # so with no HOME the very first import dies:
  #
  #   PermissionError: [Errno 13] Permission denied: '/homeless-shelter'
  #
  # That is unconditional, so it takes out pythonImportsCheckPhase as well as
  # the suite.  Upstream anticipates this — the comment above those lines says
  # "Explicitly setting the environment variable is recommended if the home
  # directory is not writable", and the `setdefault` is what makes
  # JAX_COMPILATION_CACHE_DIR work as an override.  Setting HOME instead keeps
  # the one idiom the rest of this tree uses (../aiida-core, ../strainjedi) and
  # also covers whatever else jax wants a home for, at the cost of nothing:
  # the cache is written into a build directory that is thrown away.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  nativeCheckInputs = [ pytestCheckHook ];

  # testpaths = ["tests"] is already set in pyproject.toml.
  #
  # ../wignernj's trap, and it lands harder here.  pytestCheckHook invokes
  # `python -m pytest`, which puts the working directory first on sys.path, so
  # from /build/source `import sella` resolves to the source tree rather than to
  # the installed package.  That copy is pure Python: cythonize wrote the three
  # extensions into build/lib.linux-*/, never beside the .pyx files.  So the
  # first thing every test module transitively imports is missing:
  #
  #   sella/peswrapper.py:14: in <module>
  #       from sella.utilities.math import modified_gram_schmidt
  #   E   ModuleNotFoundError: No module named 'sella.utilities.math'
  #   !!!! Interrupted: 11 errors during collection !!!!
  #
  # Loud here only because sella/__init__.py reaches the extensions on any
  # import at all.  wignernj had the same shadowing resolve to a silent skip,
  # and the whole suite reported success having run nothing — so treat the
  # noisy version as the lucky case.
  #
  # Removing the source copy makes the import resolve to the installed
  # extensions.  tests/ is a sibling directory and testpaths points at it, so
  # nothing else moves.
  preCheck = ''
    rm -rf sella
  '';

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
