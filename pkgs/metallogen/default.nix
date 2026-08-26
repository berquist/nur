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

  # There is no test suite, and this needs saying because the repository looks
  # like it has one: `MetalloGen/test.py` is 248 lines and its name matches what
  # a collector would look for by eye.  It is not a test — it is the package's
  # main entry point, defining the TMCGenerator class, and it imports
  # MetalloGen.Calculator.orca and .gaussian, which shell out to ORCA and
  # Gaussian.  Nothing in the repository asserts anything.
  #
  # pytest would not collect it in any case: `test.py` matches neither
  # `test_*.py` nor `*_test.py`, so pytestCheckHook would report success having
  # found zero items — the trap ../../AGENTS.md describes.  Naming the absence
  # here is better than a check phase that silently proves nothing.
  doCheck = false;

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
