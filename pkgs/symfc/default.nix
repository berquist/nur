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

# A backport, not a package of ours, in the same shape as ../moyopy: it exists
# because ../pypolymlp calls `Symfc.run(use_gradient_solver=...)`, an argument
# symfc added in 1.7.2, and every channel in ../../Justfile's `channels` carries
# 1.7.1 -- nixpkgs-unstable included.  Four pypolymlp tests failed on it
# (tests/test_calc/test_fc.py and test_api_fc.py, AlN and MgO each) with
#
#     TypeError: Symfc.run() got an unexpected keyword argument 'use_gradient_solver'
#
# pythonRuntimeDepsCheckHook cannot see this floor: pypolymlp names symfc only
# in its `symfc` and `tools` extras, and with no version.  So a channel below it
# builds green, and `pypolymlp-calc --fc` fails at run time.  ../phonopy at
# `main` asks for `symfc>=1.7`, which both versions meet.
#
# The materials overlay's binding is guarded, so a channel carrying 1.7.2 or
# newer keeps its own and this file goes unused there.  **Delete it once every
# leg is past 1.7.2**, and drop the binding with it.
#
# Otherwise this is nixpkgs' own derivation, as of the 1.7.1 in
# ../../flake.lock, at the v1.7.3 tag: the newest release rather than the floor,
# because 1.7.3 is a bugfix release on top of 1.7.2 and nothing here wants to
# stop short of it.
buildPythonPackage (finalAttrs: {
  pname = "symfc";
  version = "1.7.3";
  pyproject = true;
  __structuredAttrs = true;

  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/symfc.
  src = fetchFromGitHub {
    owner = "symfc";
    repo = "symfc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-jL8o+MYH8KO2dT6x+Z3+DZyS4v82x8e7wpsO6BqDhb4=";
  };

  # `setuptools_scm>=8` is in `[build-system] requires` and the version is
  # dynamic; nixpkgs' derivation lists setuptools alone.  There is no .git in a
  # fetchFromGitHub source, so setuptools-scm needs the version given to it.
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

  pythonImportsCheck = [ "symfc" ];

  nativeCheckInputs = [
    pytestCheckHook
  ];

  # Carried over from nixpkgs as it stands at 1.7.1, and not re-checked at
  # 1.7.3.  nixpkgs lists it in `disabledTests`, which becomes a `-k` substring
  # match and so also removes test_fc_basis_set_o3_wurtzite, _diamond and
  # _wurtzite_332, and test_basis_sets_O4.py's _wurtzite_221.  A node id takes
  # only the one test.  No conftest here rewrites node ids, so `--deselect`
  # sees the id as written; compare ../maggma/default.nix.
  disabledTestPaths = lib.optionals stdenv.hostPlatform.isx86_64 [
    # assert (np.float64(0.5555555555555556) == 1.0 ± 1.0e-06
    "tests/basis_sets/test_basis_sets_O3.py::test_fc_basis_set_o3"
  ];

  passthru.updatePolicy = {
    mode = "report";
    reason = "a backport for pypolymlp's use_gradient_solver, which needs >=1.7.2; delete rather than bump once every channel is past it";
  };

  meta = {
    description = "Generate symmetrized force constants";
    homepage = "https://github.com/symfc/symfc";
    changelog = "https://github.com/symfc/symfc/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
