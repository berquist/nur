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

  # The NumPy 2 incompatibility nixpkgs removed pyrr for, which is three
  # separate defects rather than the one it sounds like.  A patch file rather
  # than substituteInPlace because the middle one is a new method with a
  # fourteen-line comment, and that belongs somewhere reviewable as Python.
  #
  # 1. `np.math`, in pyrr/utils.py.  Never a NumPy API — an accidental
  #    re-export of the standard library's `math`, dropped in NumPy 2.0:
  #
  #      AttributeError: module 'numpy' has no attribute 'math'.
  #                      Did you mean: 'emath'?
  #
  #    Used exactly once, in the quadratic solver.  Costs three ray/sphere
  #    intersection tests.
  #
  # 2. Boolean ufunc results staying pyrr objects, in pyrr/objects/base.py.
  #    This is the real one, and it is a runtime bug rather than a test-only
  #    one: `np.allclose(a_vector3, something)` raises.  pyrr overloads `|` and
  #    `^` as the dot and cross products, and NumPy 2's isclose() combines its
  #    masks with exactly those operators, so a boolean Vector3 meets a Python
  #    bool inside numpy and dispatches into the dot product.  Costs sixteen
  #    tests, all in tests/objects.  See the comment in the patch for the
  #    mechanism.
  #
  # 3. `dtype=[('i', np.int16, 1), ...]` in four test modules.  A field shape of
  #    1 used to mean a scalar field and now means a shape-(1,) subarray, so
  #    `fv[0]['f']` is an array where the test wants a number, and constructing
  #    a Matrix33 from it fails with "cannot reshape array of size 1 into shape
  #    (3,3)".  Test-side only.
  #
  # With all three the suite is 434 passed, 18 skipped, 0 failed against NumPy
  # 2.5.1.  Upstream has been dormant since 2024, so none of this is waiting on
  # a release.
  patches = [ ./numpy2.patch ];

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
  # one-line substitution.  Worth doing when it becomes an error, which on
  # NumPy's usual schedule is two or three releases away.

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
