{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  fastentrypoints,
  setuptools,

  # dependencies
  aiida-core,
  click,
  pyyaml,
  pytest,
  voluptuous,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  pytest-datadir,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage {
  pname = "aiida-testing";
  version = "0.1.0-unstable-2021-05-06";
  pyproject = true;

  # Exactly the revision aiida-psi4's setup.json pins in its `testing` extra:
  #
  #   "aiida-testing @ git+https://github.com/ltalirz/aiida-testing@6b3c2ae...
  #
  # It provides the `mock_code_factory` fixture that aiida-psi4's conftest uses
  # to replay stored Psi4 outputs, which is what lets that package's tests run
  # with no Psi4 binary present.  There is no PyPI release of this fork.
  src = fetchFromGitHub {
    owner = "ltalirz";
    repo = "aiida-testing";
    rev = "6b3c2ae023157e73563630aaf24d8337c348b74b";
    hash = "sha256-2+M7E3Hj6Mh/7k6TrAte68+u5KmxHWVaF1tAbMU0pZs=";
  };

  # pyproject.toml asks for `fastentrypoints` alongside setuptools, and
  # pypaBuildPhase builds `--no-isolation`, so pythonRuntimeDepsCheckHook
  # refuses the wheel without it:
  #
  #     ERROR Unmet dependencies: fastentrypoints  wanted: any
  #                                                found: not installed
  #
  # setup.py imports it inside a try/except that only warns, so dropping it from
  # the requires list would work too.  It is cheap and nixpkgs has it, so it is
  # supplied rather than patched away — one fewer place where this package
  # differs from what upstream declares.
  build-system = [
    fastentrypoints
    setuptools
  ];

  # setup.cfg writes `aiida-core>=1.0.0<2.0.0`, with no comma between the two
  # specifiers.  packaging accepted that for years and 26.2 does not, so the
  # build dies inside pypaBuildPhase, before any of this package's own code
  # runs, in setuptools' _normalize_requires:
  #
  #     packaging.requirements.InvalidRequirement: Expected comma (within
  #     version specifier), semicolon (after version specifier) or end
  #         aiida-core>=1.0.0<2.0.0
  #                   ~~~~~~~^
  #
  # `pythonRelaxDeps` below cannot help: that hook rewrites Requires-Dist lines
  # in the built wheel's METADATA, and the failure is that there is no wheel.
  # Adding the comma is the smallest edit that lets the metadata parse at all;
  # the relaxation then drops the bound, as it was always going to.
  #
  # The second hunk is a Python 3.10 removal this 2021 fork never saw.
  # `collections.Iterable` has been the alias rather than the class since 3.3
  # and stopped existing in 3.10, so `mock_code_factory` raises
  #
  #     AttributeError: module 'collections' has no attribute 'Iterable'
  #
  # on the argument check every one of its callers goes through.  `import
  # collections` is enough to reach `collections.abc`, so the module's existing
  # import needs no companion.
  postPatch = ''
    substituteInPlace setup.cfg \
      --replace-fail "aiida-core>=1.0.0<2.0.0" "aiida-core>=1.0.0,<2.0.0"

    substituteInPlace aiida_testing/mock_code/_fixtures.py \
      --replace-fail "collections.Iterable" "collections.abc.Iterable"
  '';

  # The pin is from 2021 and names aiida-core 1.x; the fixtures themselves use
  # the plugin API that survived into 2.x.  This is the riskiest relaxation in
  # the repo — if aiida-testing turns out not to import against 2.10 at all,
  # this package and aiida-psi4's checkPhase are what will say so.
  pythonRelaxDeps = true;

  dependencies = [
    aiida-core
    click
    pyyaml
    pytest
    voluptuous
  ];

  preCheck = ''
    export PATH="$out/bin:$PATH"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  # setup.cfg's `testing` extra is `pgtest`, `pytest-datadir` and `aiida-diff`.
  # The second supplies the `datadir` fixture that tests/mock_code/test_diff.py
  # asks for; without it four of its six tests error at setup with
  # "fixture 'datadir' not found", which is a missing dependency wearing the
  # costume of a broken test.
  #
  # The third is not here, and those six tests cannot pass until it is: every
  # one of them builds a code with `entry_point='diff'` and calls
  # `CalculationFactory('diff')`.  aiida-diff is the AiiDA plugin-template
  # example package, in neither nixpkgs nor this repo.  Packaging it is the fix;
  # tests/mock_code/test_ignore_paths.py is what runs in the meantime.
  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
    pytest-datadir
  ];

  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_testing"
    "aiida_testing.mock_code"
  ];

  meta = {
    description = "pytest fixtures for testing AiiDA plugins, including mock codes";
    homepage = "https://github.com/ltalirz/aiida-testing";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
