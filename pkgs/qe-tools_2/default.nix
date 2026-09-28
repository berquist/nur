{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  numpy,
  packaging,
  scipy,

  # tests
  pytestCheckHook,
  pytest-cases,
  timeout-decorator,
}:

buildPythonPackage rec {
  # The distribution name, not the attribute's: ../aiida-quantumespresso's
  # `qe-tools~=2.0` is checked against this.
  pname = "qe-tools";
  version = "2.3.0";
  pyproject = true;

  # The 2.x line, carried beside ../qe-tools (3.x) for ../aiida-quantumespresso
  # alone.  It asks for `qe-tools~=2.0`, still at v5.1.0, and it imports
  # `qe_tools.parsers` and `qe_tools.converters.get_parameters_from_cell`: 3.x
  # removes the first and moves the second to `qe_tools.inputs`.  Delete this
  # when aiida-quantumespresso moves to 3.x.
  #
  # fetchFromGitHub rather than fetchPypi because upstream's
  # `[tool.flit.sdist]` exclude lists `tests/` outright, so the sdist cannot run
  # its own suite — with fetchPypi the pytestCheckPhase collected nothing.  Same
  # as ../disk-objectstore and ../archive-path.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "qe-tools";
    tag = "v${version}";
    hash = "sha256-NKsy9jV/VUTI8i8SFLRajqsBd2n1FwKc++vtW12Qa7Y=";
  };

  build-system = [ flit-core ];

  # Exactly upstream's `dependencies` at this tag.  scipy is not optional —
  # src/qe_tools/converters/_structure.py imports it — and leaving it out is
  # what pythonRuntimeDepsCheckHook rejected with "scipy not installed".
  #
  # xmlschema is deliberately absent: it is neither declared nor imported
  # anywhere in the 2.x source.  It belongs to the 3.x line.
  dependencies = [
    numpy
    packaging
    scipy
  ];

  # From upstream's `dev` extra, restricted to what the suite actually imports:
  # pytest_cases parametrises the input-parser cases, and timeout_decorator
  # guards the slow ones.  pytest-regressions is *not* used at 2.x — that
  # arrived with the 3.x rewrite.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-cases
    timeout-decorator
  ];

  pythonImportsCheck = [
    "qe_tools"
    "qe_tools.parsers"
    "qe_tools.converters"
  ];

  # Read by ../../scripts/update-universe.nix.  The inferred `stable` would
  # offer the newest tag, which is 3.x, and neither version guard in
  # ../../scripts/update-packages.sh objects to a well-formed version that
  # sorts forwards; that is how `2.3.0 -> 3.0.0a4` was once offered here.
  passthru.updatePolicy = {
    mode = "pinned";
    reason = "the 2.x line for aiida-quantumespresso, whose qe-tools~=2.0 excludes the 3.x that ../qe-tools follows";
  };

  meta = {
    description = "Tools for the Quantum ESPRESSO input and output formats (2.x series)";
    homepage = "https://github.com/aiidateam/qe-tools";
    changelog = "https://github.com/aiidateam/qe-tools/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
