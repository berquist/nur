# qcarchivetesting - pytest harnesses and fixtures for testing QCArchive
# components.  Not needed for production; only used when running the
# QCFractal test suite or writing integration tests.
{
  lib,
  buildPythonPackage,
  pythonAtLeast,
  fetchPypi,
  setuptools,
  versioningit,
  qcportal,
}:

buildPythonPackage rec {
  pname = "qcarchivetesting";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-HWTxXH9LX2ZSjmTmsSnZv+L5K6xwZlxuybevr3YddbM=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  # qcfractal, qcfractalcompute, qcengine, pytest and deepdiff are all in the
  # wheel's Requires-Dist, but depending on them here is a derivation-level
  # cycle — qcfractal → qcportal → (tests need) qcarchivetesting → qcfractal —
  # which Nix cannot build regardless of lazy evaluation.  Hence only qcportal
  # here and dontCheckRuntimeDeps below, which skips the hook that verifies
  # Requires-Dist entries are present in the build environment.  Nothing breaks
  # at runtime: this is a test-helper library, so its "runtime" deps are really
  # "used alongside" deps, and consumers install them together in their own
  # withPackages call or devShell.
  dependencies = [ qcportal ];

  dontCheckRuntimeDeps = true;

  # Tests require a live PostgreSQL instance; never run them at build time.
  doCheck = false;

  meta = with lib; {
    # Inherited from qcportal; see the note in ../qcportal/default.nix.
    broken = pythonAtLeast "3.14";
    description = "pytest harnesses for testing QCArchive / QCFractal components";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
