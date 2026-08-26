# nixpkgs removed pyrr on 2026-02-18:
#
#   pyrr = throw "pyrr has been removed because it is incompatible with
#          NumPy 2.0+"; # Added 2026-02-18
#
# in pkgs/top-level/python-aliases.nix, so there is no derivation left to
# revive.  It is carried here for ../molara, which cannot be patched off it —
# Vector3, Quaternion, matrix44 and vector3 are used across some forty call
# sites in rendering/camera.py and tools/raycasting.pyx.
#
# **Delete this the day nixpkgs carries pyrr again**, along with the entry in
# ../../overlays/default.nix, exactly as ../pycifrw is meant to go.
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  multipledispatch,
  numpy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "pyrr";
  # 0.10.3, not the 0.10.1 that `git describe` reports eleven commits back:
  # pyrr/version.py on this commit declares 0.10.3, and setup.py execs that
  # file to get the version.  The same tag-behind-source shape as ../fireworks.
  version = "0.10.3-unstable-2024-11-03";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "adamlwgriffiths";
    repo = "Pyrr";
    rev = "6acd3ee1e4d59fe34196a7a7f139f3b3dc2d36ee";
    hash = "sha256-fjguy2G2UxncgSf3AI6BoVGmCZYySjTTX9pc0Qr2pFE=";
  };

  build-system = [ setuptools ];

  # The entire NumPy 2 incompatibility, in one expression on one line.
  #
  # `np.math` was never a NumPy API — it was an accidental re-export of the
  # standard library's `math`, and NumPy 2.0 removed it.  pyrr uses it exactly
  # once, in the quadratic solver:
  #
  #   AttributeError: module 'numpy' has no attribute 'math'.
  #                   Did you mean: 'emath'?
  #
  # That takes out three ray/sphere intersection tests and nothing else.  With
  # this applied the suite is 331 passed, 8 skipped, 0 failed against NumPy
  # 2.5.1 — so the removal note nixpkgs left behind reads as far more sweeping
  # than the defect actually was.
  #
  # `math` is not already imported in utils.py, hence the second replacement.
  # Upstream has been dormant since 2024, so this is not waiting on a release.
  postPatch = ''
    substituteInPlace pyrr/utils.py \
      --replace-fail 'import numpy as np' 'import math
    import numpy as np' \
      --replace-fail 'np.math.sqrt' 'math.sqrt'
  '';

  dependencies = [
    multipledispatch
    numpy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # One deprecation survives and is deliberately left alone: geometry.py:519
  # assigns to `.shape` in place, which NumPy 2.5 deprecates in favour of
  # np.reshape.  It still works, it is a warning rather than an error, and
  # pyrr/objects/base.py does the same thing in BaseObject.__new__ — so fixing
  # it properly is a change to how every object type is constructed, not a
  # one-line substitution.  Worth doing when it becomes an error.

  pythonImportsCheck = [
    "pyrr"
    "pyrr.objects"
  ];

  meta = {
    description = "3D mathematical functions using NumPy";
    homepage = "https://github.com/adamlwgriffiths/Pyrr";
    changelog = "https://github.com/adamlwgriffiths/Pyrr/blob/master/CHANGELOG.md";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
