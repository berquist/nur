{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  rustPlatform,

  # dependencies
  typing-extensions,

  # tests
  numpy,
  pytestCheckHook,
}:

# A backport, not a package of ours, in the same shape as ../monty: it exists
# because ../pymatgen-core declares `moyopy>=0.17` in both its `symmetry` and
# `optional` extras, and nixos-26.05 carries 0.9.0.  The unstable legs carry
# 0.18.0 and never reach this file.
#
# The floor is a correctness floor, not a pin.  Upstream's pyproject.toml says
# so beside it --
#
#     # >=0.17: wyckoff/orbit assignments agree with spglib from this version on
#     # (0.3-0.16 disagree on a few spacegroups, see test_structure.py backend sweep)
#
# -- and on 26.05 that sweep, `test_symmetry_dataset_backends_agree_on_semantics`,
# failed for exactly three centred orthorhombic groups:
#
#     sg   moyopy 0.9.0   spglib 2.7.0
#     42   c              d
#     65   n              o
#     69   m              o
#
# Same space-group number, different Wyckoff letters: the old moyopy returns a
# wrong answer, not a crash.  Nothing caught it at build time because moyopy is
# only an extra and a check input of pymatgen-core, and
# pythonRuntimeDepsCheckHook reads neither.  Deselecting the three cases would
# have hidden a wrong answer in an extra consumers install; this replaces it.
#
# The materials overlay's binding is guarded, so a channel carrying 0.17 or
# newer keeps its own and this file goes unused there.  **Delete it once every
# leg of ../../Justfile's `channels` is past 0.17**, and drop the binding with
# it.
#
# Otherwise this is nixpkgs' own derivation, as of the 0.18.0 in ../../flake.lock,
# at the 0.17.0 tag.
buildPythonPackage (finalAttrs: {
  pname = "moyopy";
  version = "0.17.0";
  pyproject = true;
  __structuredAttrs = true;

  # The floor itself rather than the newest release, because the floor is the
  # whole reason for this file.
  src = fetchFromGitHub {
    owner = "spglib";
    repo = "moyo";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KmZx0bq7XRZViLhnFHi09UgBkysO31ZGx24egKUof3c=";
  };

  # moyopy is one crate of a Cargo workspace whose lock file sits at the
  # repository root, one directory up from the Python project.
  sourceRoot = "${finalAttrs.src.name}/moyopy";
  cargoRoot = "..";

  nativeBuildInputs = with rustPlatform; [
    cargoSetupHook
    maturinBuildHook
  ];

  env = {
    CARGO_TARGET_DIR = "./target";
  };

  # No offline answer for this one: the vendored crates come from crates.io,
  # not from a clone, so scripts/offline-src-hash.sh cannot produce it.  This
  # is the `got:` of a first build against lib.fakeHash.
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs)
      pname
      version
      src
      sourceRoot
      cargoRoot
      ;
    hash = "sha256-x2UMZcTT8nSzHX+MI60+FJnpOLEBvdVWVqNo8p/BXZQ=";
  };

  build-system = [
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
  ];

  dependencies = [
    typing-extensions
  ];

  pythonImportsCheck = [ "moyopy" ];

  nativeCheckInputs = [
    numpy
    pytestCheckHook
  ];

  # `test_interface.py` imports pymatgen at module scope, and ../pymatgen-core
  # takes this package as a check input: a cycle.  Half of what it covers is
  # covered from the other side: pymatgen-core's `get_symmetry_dataset` goes
  # through `MoyoAdapter.from_structure`, so its backend sweep -- the test this
  # file exists to make pass -- exercises that direction for all 230 groups.
  # `get_structure` and the magnetic adapters go untested.
  disabledTestPaths = [
    "python/tests/test_interface.py"
  ];

  passthru.updatePolicy = {
    mode = "report";
    reason = "a backport pinned at pymatgen-core's >=0.17 floor; delete rather than bump once 26.05 leaves the matrix";
  };

  meta = {
    description = "Python interface of moyo, a fast and robust crystal symmetry finder";
    homepage = "https://spglib.github.io/moyo/python/";
    changelog = "https://github.com/spglib/moyo/releases/tag/${finalAttrs.src.tag}";
    # `license = "MIT OR Apache-2.0"` in pyproject.toml; nixpkgs lists only the
    # second.
    license = with lib.licenses; [
      mit
      asl20
    ];
    maintainers = with lib.maintainers; [ berquist ];
  };
})
