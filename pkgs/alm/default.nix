{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,

  # build-system
  setuptools,
  wheel,
  numpy,

  # native
  boost,
  eigen,
  lapack,
  # spglib's *C* library, which the C++ core links as `-lsymspg`.  Not
  # `spglib`: in a Python package set that name is the Python binding, which
  # this package also needs and takes below.  The overlay passes nixpkgs'
  # top-level `spglib` in under this name.
  libspglib,

  # dependencies
  spglib,
}:

# ALM — the force-constant fitting library of the ALAMODE project, imported as
# `alm`.  Neither phonopy nor phono3py declares it, but both offer it as a
# force-constant calculator (`--alm`), and their suites `importorskip("alm")`
# in six and three places.  nixpkgs and NixOS-QChem both lack it.
buildPythonPackage (finalAttrs: {
  pname = "alm";
  version = "1.4.0-unstable-2024-06-02";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD rather than a tag.  The newest tag is v.0.9.8, from 2016, and the
  # Python package's own pyproject.toml has said 1.4.0 since well after it;
  # nothing was ever tagged for that.
  src = fetchFromGitHub {
    owner = "ttadano";
    repo = "ALM";
    rev = "f1d668fdee66e7e7218a04c88daf19d0e14fce0c";
    hash = "sha256-DKhDH0zQ0xJxhA1tC9AWt6r9YHzn7lCThtpPI2eIiv0=";
  };

  # The Python package is in python/, and its setup.py compiles the C++ core
  # out of `../src` when there is no `src` beside it — which is exactly the
  # layout this leaves.
  sourceRoot = "${finalAttrs.src.name}/python";

  # Two repairs to python/pyproject.toml.
  #
  # `readme = "README.md"` names a file one directory up, so setuptools fails
  # to find it from here; it is copied in rather than the line dropped, so the
  # wheel's long description is upstream's.
  #
  # `[project.scripts]` declares `alm = "alm:main"`, and `alm` has no `main` —
  # `alm/__init__.py` exports `ALM` and `optimizer_control_data_types` and
  # nothing else.  The script would install and then die with an
  # AttributeError on first use, so it is removed instead.
  postPatch = ''
    cp ../README.md .
    substituteInPlace pyproject.toml \
      --replace-fail 'alm = "alm:main"' ""
  '';

  build-system = [
    setuptools
    wheel
    numpy
  ];

  # setup.py looks for Eigen under `$CONDA_PREFIX/include/eigen3`; that path
  # does not exist here, so Eigen's own include directory is added instead.
  # Boost, LAPACK and libsymspg are found on the compiler's ordinary paths.
  buildInputs = [
    boost
    eigen
    lapack
    libspglib
  ];

  env.NIX_CFLAGS_COMPILE = "-isystem ${lib.getDev eigen}/include/eigen3";

  dependencies = [
    numpy
    spglib
  ];

  # Upstream has no test suite, only two example fits in test/ — silicon and
  # silicon carbide, against displacement and force data shipped beside them.
  # Neither asserts anything, but each runs the whole C++ path (symmetry
  # through spglib, cluster enumeration, the Eigen fit) and exits non-zero if
  # any of it fails, which is what this needs to know.  The real assertions are
  # ../phonopy's and ../phono3py's `alm` tests, which this package exists for.
  checkPhase = ''
    runHook preCheck

    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"
    pushd ../test
    python Si_fitting.py
    python SiC_fitting.py
    popd

    runHook postCheck
  '';

  pythonImportsCheck = [
    "alm"
    "alm._alm"
  ];

  meta = {
    description = "Force-constant fitting library from the ALAMODE project";
    homepage = "https://github.com/ttadano/ALM";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
