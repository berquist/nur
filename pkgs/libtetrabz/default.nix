{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  numpy,
  setuptools,
  wheel,

  # tests
  python,
}:

buildPythonPackage {
  pname = "libtetrabz";
  version = "0.1.2-unstable-2025-11-22";
  pyproject = true;

  # The optimized tetrahedron method for Brillouin-zone integrals, as its
  # Python binding: ../pheasy's `extras`, for its tetrahedron DOS.
  #
  # `-unstable-` although 0.1.2 is what setup.py says, because the binding has
  # never been tagged.  The tags, 1.0 to 2.0.0, version the C and Fortran
  # library beside it, and the updater would read 2.0.0 as a release of this.
  # 0.1.2 is cde26fc, "support numpy 2.0.0"; pheasy pins 0.1.1, which predates
  # ddc53cf's `numpy.float_ -> numpy.float64` and so cannot import on numpy 2.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in
  # wc/libtetrabz.
  src = fetchFromGitHub {
    owner = "mitsuaki1987";
    repo = "libtetrabz";
    rev = "cde26fc13e66c41ca30e14d49eb7a8445d81266a";
    hash = "sha256-jKOKuTqum0koVIKAhaVfqPpvLGX8cuHwulo5Q2/khMI=";
  };

  sourceRoot = "source/python";

  build-system = [
    numpy
    setuptools
    wheel
  ];

  dependencies = [ numpy ];

  # src/test.py runs each integrator on a model band structure and prints the
  # analytic value beside the computed one; it asserts nothing, so
  # this proves the extension builds and runs rather than that it is right.
  # Copied out first: run in place, `src/` is sys.path[0] and the uncompiled
  # package there shadows the installed one.
  checkPhase = ''
    runHook preCheck
    cp src/test.py "$TMPDIR/libtetrabz_test.py"
    ${python.interpreter} "$TMPDIR/libtetrabz_test.py"
    runHook postCheck
  '';

  pythonImportsCheck = [ "libtetrabz" ];

  meta = {
    description = "Optimized tetrahedron method for Brillouin-zone integrals";
    homepage = "https://mitsuaki1987.github.io/libtetrabz/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
