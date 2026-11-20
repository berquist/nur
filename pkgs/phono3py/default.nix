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
  pypolymlp,
  pyyaml,
  alm,
}:

# phono3py — phonon-phonon interaction and lattice thermal conductivity, the
# sibling of phonopy.  Carried for `matcalc[phonon3]`.
#
# **Tied to phonopy's minor version.**  Every release pins
# `phonopy>=X.Y,<X.(Y+1)`, and the pin is real: phono3py 4.7 calls
# `get_tetrahedra_relative_gr_grid_address`, which phonopy 4.4 does not have.
# So this is only ever buildable against the one phonopy minor it was cut for,
# and ../phonopy exists in this repository to make that the same minor on every
# channel.  `meta.broken` and `passthru.updatePolicy` below both follow from it.
buildPythonPackage (finalAttrs: {
  pname = "phono3py";
  version = "4.10.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phono3py";
    tag = "v${finalAttrs.version}";
    hash = "sha256-5gdow/reGvnDpvekAen+46h/BS+GAJLUaJs4AuL59lg=";
  };

  # scikit-build-core takes the version from setuptools_scm
  # (`metadata.version.provider`), which needs a repository fetchFromGitHub does
  # not provide.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `nanobind < 2.10.0` in the build requirements; nixpkgs carries 2.13, and
  # phono3py's bindings use the ordinary `nb::module_` / `nb::ndarray` surface.
  # A build-system pin, so it has to be rewritten in pyproject.toml —
  # `pythonRelaxDeps` only touches the wheel's runtime metadata.
  #
  # `test_reciprocal_to_normal_vs_c` compares the Python reciprocal-to-normal
  # transform with the compiled one at `rtol=1e-10, atol=0`.  Sixteen of the 216
  # entries are zero by symmetry, and both sides compute them as rounding noise
  # near 1e-40.  With no `atol`, the test compares noise with noise:
  #
  #     Mismatched elements: 16 / 216 (7.41%)
  #      [0, 4, 1]: 6.330858610203191e-41 (ACTUAL), 2.104729304428205e-41 (DESIRED)
  #
  # The result depends on the CPU.  One derivation, with identical inputs,
  # passed on one builder and failed on another.  On the failing kind of
  # machine, the largest difference across all 216 entries is 2.4e-16 of the
  # largest entry (6.9e-9), which is the exact double-precision rounding level.
  # The two populations are far apart: the noise entries are at most 5e-38, and
  # the smallest real entry is 1.4e-13.  An `atol` of 1e-16 times the largest
  # entry (7e-25) is five orders above the noise.  For the smallest real entry
  # it is 5e-12 relative, which is still stricter than `rtol`, so no real
  # entry is judged more loosely than before.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"nanobind<2.10.0"' '"nanobind"'

    substituteInPlace test/phonon3/test_reciprocal_to_normal.py \
      --replace-fail \
        'np.testing.assert_allclose(py_interaction, c_interaction[0], rtol=1e-10, atol=0)' \
        'np.testing.assert_allclose(py_interaction, c_interaction[0], rtol=1e-10, atol=1e-16 * np.abs(c_interaction[0]).max())'
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

  # pypolymlp unchecked, for the reason given at ../phonopy's
  # `nativeCheckInputs`: ../pypolymlp's own suite imports this package, so a
  # checked one here would be a dependency loop.  Four tests `importorskip` it.
  # symfc, which eighteen more ask for, arrives through phonopy.  ../alm, for
  # three more, is declared nowhere upstream and is a check input for the same
  # reason as at ../phonopy.
  nativeCheckInputs = [
    pytestCheckHook
    alm
    h5py
    pyyaml
    (pypolymlp.overridePythonAttrs { doCheck = false; })
  ];

  pythonImportsCheck = [
    "phono3py"
    "phono3py.phonon3.interaction"
  ];

  # Read by ../../scripts/update-universe.nix, which would otherwise infer
  # `stable` and offer the newest tag on its own.  A phono3py bump that crosses
  # a minor needs the matching ../phonopy bump in the same change, and neither
  # builds without the other, so the updater reports it and a human does both.
  passthru.updatePolicy = {
    mode = "report";
    reason = "pinned to phonopy's minor version; bump together with ../phonopy";
  };

  meta = {
    description = "Phonon-phonon interaction and lattice thermal conductivity";
    homepage = "https://phonopy.github.io/phono3py/";
    license = lib.licenses.bsd3;
    mainProgram = "phono3py";
    maintainers = with lib.maintainers; [ berquist ];
    # Under overlays.materials phonopy is always at least ../phonopy's version
    # — ours where the channel is older, the channel's own where it is not.  So
    # this fires only once a channel moves past that minor, which is the signal
    # to bump both.
    broken = lib.versions.majorMinor phonopy.version != lib.versions.majorMinor finalAttrs.version;
  };
})
