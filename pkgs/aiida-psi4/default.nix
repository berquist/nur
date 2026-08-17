{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  wheel,

  # dependencies
  aiida-core,
  qcelemental,
  sqlalchemy,

  # tests
  pytestCheckHook,
  aiida-testing,
  pgtest,
  postgresql,
}:

buildPythonPackage {
  pname = "aiida-psi4";
  version = "0.1.0a0-unstable-2026-08-16";
  pyproject = true;

  # No tags and no PyPI release; `master` is where it has always lived.
  src = fetchFromGitHub {
    owner = "ltalirz";
    repo = "aiida-psi4";
    rev = "637e6b0b29e724a158014269d55d9091c6af48c7";
    hash = "sha256-JMdYxwU3z7cgOIgbzbKslxzcr3pKtKKSSRXSTSWc+v8=";
  };

  # There is no [project] table and no [build-system] table either — the whole
  # distribution is a legacy setup.py that json-loads setup.json and splats it
  # into setup().  `build` falls back to setuptools + wheel for exactly this
  # case, so they are named explicitly rather than left to a default.
  build-system = [
    setuptools
    wheel
  ];

  # This package is AiiDA-1.x-era metadata wrapped around AiiDA-2-compatible
  # code, and the two have to be reconciled by hand.
  #
  # `setup_requires: ["reentry"]` is the load-bearing removal: setuptools
  # resolves setup_requires by *downloading* at build time, which a fixed-output
  # build cannot do.  `reentry_register` is the hook that used to rebuild
  # AiiDA 1.x's entry-point cache and has no counterpart in 2.x, where entry
  # points are read from importlib.metadata directly.
  #
  # tests/test_data.py imports ValidationError from `pydantic.error_wrappers`,
  # the pydantic-1 location.  aiida-core pulls pydantic 2, where that module is
  # a migration stub that raises on attribute access — but qcelemental's v1
  # models (which AtomicInput is built on) validate through `pydantic.v1`, so
  # the exception the test wants really is the v1 one, just under its new name.
  postPatch = ''
    substituteInPlace setup.json \
      --replace-fail '"setup_requires": ["reentry"],' "" \
      --replace-fail '"reentry_register": true,' ""

    substituteInPlace tests/test_data.py \
      --replace-fail 'from pydantic.error_wrappers import ValidationError' \
                     'from pydantic.v1.error_wrappers import ValidationError'
  '';

  # setup.json still declares `aiida-core>=1.6.4,<2.0.0`, `sqlalchemy<1.4` and
  # `qcelemental~=0.20.0`, all from 2021.  Every import in aiida_psi4/ —
  # aiida.engine, aiida.orm, aiida.plugins, aiida.parsers.parser, aiida.common —
  # is on the API that survived into 2.x, and the package does not touch
  # SQLAlchemy itself at all, so these are stale bounds rather than real ones.
  pythonRelaxDeps = [
    "aiida-core"
    "qcelemental"
    "sqlalchemy"
  ];

  dependencies = [
    aiida-core
    qcelemental
    sqlalchemy
  ];

  nativeCheckInputs = [
    pytestCheckHook

    # conftest.py loads `aiida_testing.mock_code` as a pytest plugin; see
    # ../aiida-testing for why that is a git-pinned fork rather than a release.
    aiida-testing

    # conftest.py also loads `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, whose profile is config_psql_dos({}) and so needs a
    # real PostgreSQL.  See ../pgtest for why postgresql is listed too.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # Upstream's addopts is `--durations=0 --cov=aiida_psi4`, which needs
  # pytest-cov for output that is thrown away.  Same treatment as aiida-core.
  pytestFlags = [ "--override-ini=addopts=" ];

  # `testpaths` covers tests/ *and* examples/, and `python_files` is widened to
  # match `example_*.py`, so both are collected — deliberately, and it works
  # here: the examples run through aiida-testing's mock code, which replays the
  # stored Psi4 output under tests/data/ instead of executing anything.  No Psi4
  # binary is involved, which is the whole point of the mock_code fixture.

  pythonImportsCheck = [
    "aiida_psi4"
    "aiida_psi4.data"
    "aiida_psi4.calculations"
    "aiida_psi4.parsers"
  ];

  meta = {
    description = "AiiDA plugin for the Psi4 quantum chemistry package";
    homepage = "https://github.com/ltalirz/aiida-psi4";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
