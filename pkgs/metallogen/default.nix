{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  numpy,
  pulp,
  rdkit,
  scipy,

  # tests
  pytestCheckHook,

  # cclib is not in nixpkgs and arrives from a flake input, which
  # ../../overlays/default.nix cannot reach.  Defaulted rather than required so
  # that evaluation still succeeds on the bare NUR path — `nix-env -f . -qa '*'`
  # forces every attribute — with meta.broken below keeping `just ci-build` from
  # attempting it.  See ../harmonwig/default.nix for the full explanation.
  cclib ? null,
}:

buildPythonPackage {
  pname = "metallogen";
  version = "0.0.1-unstable-2025-12-04";
  pyproject = true;

  # No tags have ever been pushed, so a commit is the only thing to pin.  The
  # version is what setup.py declares.
  src = fetchFromGitHub {
    owner = "kyunghoonlee777";
    repo = "MetalloGen";
    rev = "fa26e2adb996ed2256e528e1c97fbc1c363c0808";
    hash = "sha256-mV7ao5Hmp6lEwXh7Mk/6zd5c+jAHZp9gE0q+9TnRmWo=";
  };

  build-system = [ setuptools ];

  dependencies = [
    cclib
    numpy
    pulp
    rdkit
    scipy
  ];

  # Upstream ships no test suite, and the repository looks like it does:
  # `MetalloGen/test.py` is 248 lines and its name matches what a collector
  # would look for by eye.  It is not a test — it is the package's main entry
  # point, defining TMCGenerator, and it imports MetalloGen.Calculator.orca and
  # .gaussian, which shell out to ORCA and Gaussian.  Nothing upstream asserts
  # anything.  pytest would not collect it either: `test.py` matches neither
  # `test_*.py` nor `*_test.py`, so a bare pytestCheckHook would report success
  # having found zero items, which is the trap ../../AGENTS.md describes.
  #
  # So ./tests/test_examples.py is ours.  It is built out of upstream's own
  # examples/ directory, which the sdist would not have carried but the git
  # checkout does: each `commands` file records a real invocation and the
  # result_*.xyz files beside it record what that invocation produced.  The
  # invocations cannot be replayed — they drive Gaussian, ORCA or xtb through
  # absolute paths on someone else's machine — but the inputs and the recorded
  # outputs together pin down everything that does not need a quantum chemistry
  # program: the mSMILES parser, the SDF reader, and the geometry tables both
  # consult.  34 tests, one of them an expected failure; see the module
  # docstring for why the cross-checks are the valuable part.
  #
  # Copied in rather than applied as a patch so it stays a real Python file that
  # can be linted and run on its own, the way ../../AGENTS.md asks of scripts.
  preCheck = ''
    mkdir -p tests
    cp ${./tests/test_examples.py} tests/test_examples.py
  '';

  nativeCheckInputs = [ pytestCheckHook ];

  enabledTestPaths = [ "tests/test_examples.py" ];

  # Deliberately only the top-level package.  Importing MetalloGen.test would
  # drag in the ORCA and Gaussian calculator wrappers, which is not something to
  # require at build time.
  pythonImportsCheck = [ "MetalloGen" ];

  meta = {
    description = "Generate 3D structures of organometallic complexes";
    homepage = "https://github.com/kyunghoonlee777/MetalloGen";
    license = lib.licenses.bsd3;
    mainProgram = "metallogen";
    maintainers = with lib.maintainers; [ berquist ];
    broken = cclib == null;
  };
}
