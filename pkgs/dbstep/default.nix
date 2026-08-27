{
  lib,
  buildPythonApplication,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  numpy,
  scipy,

  # cclib comes from a flake input that ../../overlays/default.nix cannot
  # reach; see ../harmonwig/default.nix for the full explanation of the
  # defaulted-argument-plus-meta.broken arrangement.  Here it really is a hard
  # dependency: dbstep/parse_data.py does `import cclib` at module scope, and
  # that module is what Dbstep.py reads every input file through.
  cclib ? null,

  # tests
  pytestCheckHook,
}:

buildPythonApplication {
  pname = "dbstep";
  version = "1.1.0-unstable-2026-03-17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "patonlab";
    repo = "DBSTEP";
    rev = "2c7461b8bd95911f7e87d6d7f540fa50fa1122af";
    hash = "sha256-egyvQbJralKc3yTTU6ncDYmPRS8ya2jtLOLothrMBlg=";
  };

  build-system = [ setuptools ];

  dependencies = [
    numpy
    scipy
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [ pytestCheckHook ];

  # dbstep.graph is deliberately absent from the import check.  It imports
  # rdkit and pandas at module scope, which upstream keeps in the `graph2d`
  # extra rather than in `dependencies` — so importing it here would turn an
  # optional feature into a hard requirement.  Nothing under tests/ touches it.
  #
  # dbstep/sterics.py's `import pptk` is likewise not a dependency: it sits
  # inside `if options.debug:`, and pptk is a point-cloud viewer that is not in
  # nixpkgs and has no wheel for any current interpreter.
  pythonImportsCheck = [
    "dbstep"
    "dbstep.Dbstep"
    "dbstep.calculator"
    "dbstep.parse_data"
    "dbstep.sterics"
  ];

  meta = {
    description = "DFT-based steric parameters — Sterimol values and buried volumes";
    homepage = "https://github.com/patonlab/DBSTEP";
    license = lib.licenses.mit;
    mainProgram = "dbstep";
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through the flake; see the cclib argument above.
    broken = cclib == null;
  };
}
