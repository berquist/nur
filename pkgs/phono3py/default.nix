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
  version = "4.5.0-unstable-2026-09-26";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phono3py";
    rev = "3a69b1bbae572063f2a2c7a8ef5ee1a202a74a9c";
    hash = "sha256-5C5vew03sl5lOD/jDy3vCeGSvmGQeHiKoABpsEQRgzg=";
  };

  # scikit-build-core takes the version from setuptools_scm
  # (`metadata.version.provider`), which needs a repository fetchFromGitHub does
  # not provide.  The `-unstable-` suffix is not PEP 440.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  # `nanobind < 2.10.0` in the build requirements; nixpkgs carries 2.13, and
  # phono3py's bindings use the ordinary `nb::module_` / `nb::ndarray` surface.
  # A build-system pin, so it has to be rewritten in pyproject.toml —
  # `pythonRelaxDeps` only touches the wheel's runtime metadata.
  #
  # test_reciprocal_to_normal_vs_c compares the Python ReciprocalToNormal with
  # the compiled interaction strength at `rtol=1e-10, atol=0`.  Here 16 of its
  # 216 elements disagreed, all of them between 1e-41 and 1e-39, while the other
  # 200 agreed to 1e-10.  For scale, the sibling regression test's per-band sums
  # of |fc3|^2 are 8e-6 to 2.5e-4 before the unit factor.  Those 16 are
  # presumably residues of terms that cancel to zero, and the two paths sum in a
  # different order; with no absolute floor, the test compares that noise at a
  # relative 1e-10, and it passes or fails with the toolchain.  The floor is
  # 1e-10 of the largest element, so every element that matters still gets the
  # same 1e-10 relative check.  Patched rather than deselected so that the check
  # of the real values stays.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"nanobind<2.10.0"' '"nanobind"'

    substituteInPlace test/phonon3/test_reciprocal_to_normal.py \
      --replace-fail \
        'np.testing.assert_allclose(py_interaction, c_interaction[0], rtol=1e-10, atol=0)' \
        'np.testing.assert_allclose(py_interaction, c_interaction[0], rtol=1e-10, atol=1e-10 * np.abs(c_interaction[0]).max())'
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
    # This `main` pins `phonopy>=4.6.0,<4.7.0` and needs more than that: it
    # imports a function phonopy added after tagging 4.6.0.  The materials
    # overlay supplies phonopy `main` as ../phonopy; this guards the case of a
    # phonopy from anywhere else, such as nixos-26.05's 3.5.1.
    broken = lib.versionOlder phonopy.version "4.6";
  };
})
