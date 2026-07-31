# qcarchivetesting - pytest harnesses and fixtures for testing QCArchive
# components.  Not needed for production; only used when running the
# QCFractal test suite or writing integration tests.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  qcportal,
  # qcfractal,
  # qcfractalcompute,
  # pytest,
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

  dependencies = [
    # qcfractal, qcfractalcompute, qcengine, pytest, and deepdiff are all
    # listed in the wheel's Requires-Dist, but including them here creates
    # a derivation-level cycle:
    #   qcfractal → qcportal → (tests need) qcarchivetesting → qcfractal
    # Nix cannot build circular derivation graphs regardless of lazy evaluation.
    #
    # The fix is dontCheckRuntimeDeps below, which skips the hook that verifies
    # Requires-Dist entries are present in the build environment.  The package
    # still works correctly at runtime because consumers install it alongside
    # the other packages in a python.withPackages call or devShell, where all
    # dependencies are present.
    qcportal
  ];

  # Skip the pythonRuntimeDepsCheckHook: qcarchivetesting's wheel metadata
  # declares qcfractal and qcfractalcompute as runtime deps, which would form
  # a cycle with those packages' own test deps.  This is a known upstream
  # packaging quirk — qcarchivetesting is a test helper library, not a
  # standalone application, so its "runtime" deps are really "used alongside"
  # deps rather than hard install-time requirements.
  dontCheckRuntimeDeps = true;

  # Tests require a live PostgreSQL instance; never run them at build time.
  doCheck = false;

  # pythonImportsCheck = [ "qcarchivetesting" ];

  meta = with lib; {
    description = "pytest harnesses for testing QCArchive / QCFractal components";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
