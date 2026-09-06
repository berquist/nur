{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  scikit-build-core,
  nanobind,
  setuptools-scm,
  cmake,
  ninja,

  # native
  blas,
  lapack,

  # dependencies
  numpy,
  phonopy,

  # tests
  pytestCheckHook,
  h5py,
  pyyaml,
}:

# phono3py — phonon-phonon interaction and lattice thermal conductivity, the
# sibling of phonopy.  Carried for `matcalc[phonon3]`.
buildPythonPackage (finalAttrs: {
  pname = "phono3py";
  version = "4.4.0-unstable-2026-09-04";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phono3py";
    rev = "2bacd16988fd37dfb419c717841d1a29a2f7bbad";
    hash = "sha256-sVzlXLSWwebR/h5tnYCj9vVXQ9q4CXuH6mmbw1uZtkI=";
  };

  # scikit-build-core takes the version from setuptools_scm
  # (`metadata.version.provider`), which needs a repository fetchFromGitHub does
  # not provide.  The `-unstable-` suffix is not PEP 440.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  # `nanobind < 2.10.0` in the build requirements; nixpkgs carries 2.13, and
  # phono3py's bindings use the ordinary `nb::module_` / `nb::ndarray` surface.
  # A build-system pin, so it has to be rewritten in pyproject.toml —
  # `pythonRelaxDeps` only touches the wheel's runtime metadata.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"nanobind<2.10.0"' '"nanobind"'
  '';

  # `USE_CONDA_PATH` defaults ON and points CMake at a conda prefix; off here.
  # `BUILD_WITHOUT_LAPACKE` is already the upstream default, so LAPACKE is not
  # needed — a plain BLAS covers `PHONO3PY_USE_MTBLAS`.
  env.USE_CONDA_PATH = "OFF";

  build-system = [
    scikit-build-core
    nanobind
    setuptools-scm
  ];

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [
    blas
    lapack
  ];

  dontUseCmakeConfigure = true;

  dependencies = [
    numpy
    phonopy
  ];

  nativeCheckInputs = [
    pytestCheckHook
    h5py
    pyyaml
  ];

  pythonImportsCheck = [
    "phono3py"
    "phono3py.phonon3.interaction"
  ];

  meta = {
    description = "Phonon-phonon interaction and lattice thermal conductivity";
    homepage = "https://phonopy.github.io/phono3py/";
    license = lib.licenses.bsd3;
    mainProgram = "phono3py";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
