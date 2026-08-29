{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  decorator,
  numpy,
  pyyaml,
  scipy,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-optimize";
  version = "1.0.2";
  pyproject = true;

  # Not fetchPypi, for the usual reason — the sdist carries no `tests/` — and
  # here the suite is also where `sample_processes.py` lives, which every test
  # module imports.  See ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "greschd";
    repo = "aiida-optimize";
    tag = "v${version}";
    hash = "sha256-6ZxgnsYk7u+9njNAbXDQ5bqeu+jkG/gHc4O1gxcombs=";
  };

  build-system = [ setuptools ];

  # See ../aiida-orca/default.nix: our aiida-core is a pre-release, which
  # `aiida-core>=2.0.0,<3.0.0` does not admit.
  pythonRelaxDeps = [ "aiida-core" ];

  # setup.py carries no metadata of its own — it reads setup.json and splices
  # it into `setup()`, so `install_requires` is the list in that file.
  dependencies = [
    aiida-core
    decorator
    numpy
    pyyaml
    scipy
  ];

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, whose profile is a real PostgreSQL one.  See ../pgtest
    # for why postgresql is listed alongside it.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_optimize"
    "aiida_optimize.engines"
    "aiida_optimize.wrappers"
  ];

  meta = {
    description = "AiiDA plugin for running optimization algorithms";
    homepage = "https://github.com/greschd/aiida-optimize";
    # Apache 2.0 for the program, BSD-3 for one file.
    #
    # LICENSE.txt is the Apache 2.0 text and setup.json's `license` says
    # "Apache 2.0", as does the PyPI classifier.  ADDITIONAL_TERMS.txt calls
    # LICENSE.txt "GPLv3" in passing, which is stale wording rather than a
    # third license — the file it actually governs,
    # aiida_optimize/engines/_nelder_mead.py, is derived from SciPy's
    # optimize.py and carries the Enthought/SciPy BSD-3 notice.  That is what
    # the second entry is.
    #
    # A list rather than one license: ci.nix's `isBuildable` normalises either
    # shape and requires every entry to be free, which both of these are.
    license = with lib.licenses; [
      asl20
      bsd3
    ];
    maintainers = with lib.maintainers; [ berquist ];
  };
}
