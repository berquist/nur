{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  ase,
  jax,
  jaxlib,
  numpy,
  scipy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "sella";
  version = "2.6.0-unstable-2026-09-02";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zadorlab";
    repo = "sella";
    rev = "6cfb60cdb100a146c3c6f0587d5308b247aa8010";
    hash = "sha256-jeRqzXy9mPTVSbE6OavJW56bqreVIC8jKgDUatBOGl4=";
  };

  build-system = [
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
  # Deriving it from `version` rather than repeating "2.6.0" keeps the two from
  # drifting when this is next bumped — which it since has been, from 2.5.0, with
  # nothing to change here.
  #
  # That leaves the installed metadata saying 2.6.0 while the derivation says
  # 2.6.0-unstable-2026-09-02, which is fine: mk-python-derivation.nix skips
  # pythonMetadataCheckPhase entirely for any version containing "unstable-".
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" version);

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"setuptools >= 74.1.0, < 82",' '"setuptools >= 74.1.0",'
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

  preCheck = ''
    rm -rf sella
  '';

  pythonImportsCheck = [
    "sella"
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
