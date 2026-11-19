{
  lib,
  stdenv,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  numpy,
  scipy,
  spglib,

  # tests
  pytestCheckHook,
}:

# symfc — symmetry-adapted force-constant fitting, which phonopy uses for its
# `--fc-calculator symfc` path.
#
# A guarded backport, like ../phonors and for the same dependant: ../phonopy
# 4.10 declares `symfc>=1.8`, and every channel here has 1.7.1.  The floor is an
# API one — phonopy 7558bbae, "Pass Symmetry and symprec to symfc projector",
# raised it.  See the `symfc` binding in ../../overlays/default.nix.
buildPythonPackage (finalAttrs: {
  pname = "symfc";
  version = "1.8.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "symfc";
    repo = "symfc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ROjPa1cVXzXnpChLY86RSOnWfMlpc2ykO1BTWZBWel4=";
  };

  # New in 1.8: the version comes from setuptools-scm (`version_file`), which
  # 1.7.1 did not use.  Pinned rather than left to the hook, the same reason
  # ../torch-pme and ../dargs pin theirs.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    numpy
    scipy
    spglib
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # Carried over from nixpkgs' 1.7.1 derivation, which records the failure as
  #
  #   assert (np.float64(0.5555555555555556) == 1.0 ± 1.0e-06
  #
  # on x86_64.  Not re-derived for 1.8.0: if it passes now, the build will not
  # say so, and this entry should go.
  #
  # A node id rather than nixpkgs' `disabledTests` entry, which is a `-k`
  # substring: `test_fc_basis_set_o3` also matches `_o3_wurtzite`,
  # `_o3_diamond`, `_o3_wurtzite_332` and, in test_basis_sets_O4.py,
  # `_o3_wurtzite_221`, so nixpkgs has been skipping five tests to drop one.
  disabledTestPaths = lib.optionals stdenv.hostPlatform.isx86_64 [
    "tests/basis_sets/test_basis_sets_O3.py::test_fc_basis_set_o3"
  ];

  pythonImportsCheck = [ "symfc" ];

  meta = {
    description = "Generate symmetrized force constants";
    homepage = "https://github.com/symfc/symfc";
    changelog = "https://github.com/symfc/symfc/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
