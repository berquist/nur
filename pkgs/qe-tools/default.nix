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
  pname = "qe-tools";
  version = "2.3.0";
  pyproject = true;

  # aiida-quantumespresso asks for `qe-tools~=2.0`, i.e. anything in the 2.x
  # series.  Upstream is on 3.0.0aN now, and that is a deliberate hold rather
  # than staleness: 3.x removes `qe_tools.parsers` and moves
  # get_parameters_from_cell out of `qe_tools.converters`, both of which
  # ../aiida-quantumespresso imports.  It also picks up a hard dependency on
  # `dough`, which nixpkgs does not carry.
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

  meta = {
    description = "Tools for the Quantum ESPRESSO input and output formats";
    homepage = "https://github.com/aiidateam/qe-tools";
    changelog = "https://github.com/aiidateam/qe-tools/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
