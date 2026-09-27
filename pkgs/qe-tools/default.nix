{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  dough_0_4,
  glom,
  numpy,
  packaging,
  xmlschema,

  # optional-dependencies
  aiida-core,
  ase,
  pymatgen,

  # tests
  pytestCheckHook,
  pytest-cases,
  pytest-regressions,
  timeout-decorator,
}:

buildPythonPackage rec {
  pname = "qe-tools";
  version = "3.0.0a4";
  pyproject = true;

  # The 3.x rewrite, and not what ../aiida-quantumespresso runs on: that asks
  # for `qe-tools~=2.0` and imports `qe_tools.parsers`, which 3.x removed.  It
  # takes ../qe-tools_2 instead.  The two cannot share an environment, since
  # both install `qe_tools`, and upstream's pins say the same thing.
  #
  # fetchFromGitHub for the suite, as with the 2.x line: the regression
  # snapshots under tests/outputs are what most of it checks against.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "qe-tools";
    tag = "v${version}";
    hash = "sha256-L71cDjOXdSjX9ZGFMtEMfn4O8+mbOKRVc2anSNZB9aY=";
  };

  build-system = [ hatchling ];

  # `glom~=24.11` against nixpkgs' 25.12.0.  qe-tools uses Spec, Coalesce, Check
  # and T, the long-standing core of glom's API.
  #
  # dough is *not* relaxed.  The pin is `dough==0.4.0` and ../dough_0_4 is
  # exactly that, because 0.5 removed `dough.outputs.output_mapping`, which four
  # modules under qe_tools/outputs import.  ../dough is 0.6 and would fail at
  # import, not at a version check.
  pythonRelaxDeps = [ "glom" ];

  dependencies = [
    dough_0_4
    glom
    numpy
    packaging
    xmlschema
  ];

  # Upstream's extras, less `docs`, `tests` and `pre-commit`.  `pint` is
  # `dough[pint]`, so it is dough_0_4's own extra rather than a second copy of
  # the pin.  The converters import their library lazily and raise with an
  # install hint, so none of these is needed to import qe_tools.
  optional-dependencies = {
    aiida = [ aiida-core ];
    ase = [ ase ];
    pint = dough_0_4.optional-dependencies.pint;
    pymatgen = [ pymatgen ];
  };

  # Upstream's hatch-test environment is `features = ["tests", "ase",
  # "pymatgen"]`, and test_ase_outputs and test_pymatgen_outputs are the tests
  # that need the second and third.  Nothing in tests/ reaches the aiida or pint
  # converters, so aiida-core stays out of the check closure.
  #
  # pytest-regressions backs the `robust_data_regression_check` fixture, which
  # tests/conftest.py loads from `dough.testing.plugin`; that plugin ships in the
  # dough wheel, so no sys.path arrangement is needed.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-cases
    pytest-regressions
    timeout-decorator
  ]
  ++ optional-dependencies.ase
  ++ optional-dependencies.pymatgen;

  pythonImportsCheck = [
    "qe_tools"
    "qe_tools.converters"
    "qe_tools.inputs"
    "qe_tools.outputs"
  ];

  meta = {
    description = "Tools for the Quantum ESPRESSO input and output formats";
    homepage = "https://github.com/aiidateam/qe-tools";
    changelog = "https://github.com/aiidateam/qe-tools/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
