{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  glom,

  # tests
  pytestCheckHook,
  numpy,
  pint,
  pydantic,
  pytest-regressions,
  pyyaml,
}:

buildPythonPackage rec {
  pname = "dough";
  version = "0.6.0-unstable-2026-06-19";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mbercx";
    repo = "dough";
    rev = "0626e780307cf9032e90fe6d68961ffff0eeaea2";
    hash = "sha256-7CelDrwJO/8Pbdd+9pa5bgv3mK7Z/+Q1t6aBAMrkM5U=";
  };

  build-system = [ hatchling ];

  # hatch reads the version from src/dough/__about__.py rather than from git, so
  # unlike ../sella there is no setuptools-scm-shaped hole to fill here.

  dependencies = [ glom ];

  # `pint` and `pydantic` are optional at runtime — they back the two converter
  # layers and are declared as extras — but the `tests` extra pulls in
  # `dough[all]`, so the suite exercises both.  Leaving them out would not fail;
  # it would silently reduce what runs.
  nativeCheckInputs = [
    pytestCheckHook
    numpy
    pint
    pydantic
    pytest-regressions
    pyyaml
  ];

  # tests/conftest.py sets `pytest_plugins = ["dough.testing.plugin"]`, which is
  # shipped inside the package rather than being a test-only file, so no extra
  # sys.path arrangement is needed.

  pythonImportsCheck = [
    "dough"
    "dough.converters"
    "dough.inputs"
    "dough.outputs"
  ];

  meta = {
    description = "Framework for building typed Python wrappers around simulation code output files";
    homepage = "https://github.com/mbercx/dough";
    changelog = "https://github.com/mbercx/dough/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
