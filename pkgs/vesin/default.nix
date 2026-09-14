{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  cmake,

  # build-system
  setuptools,

  # dependencies
  numpy,

  # tests
  pytestCheckHook,
  ase,
  pytest-timeout,
  torch,
}:

# vesin — neighbour lists for atomistic systems: a small C++ library with a
# numpy front end, from the metatensor group.
#
# Here as a check input twice over.  ../torch-pme's `tests/helpers.py` imports
# `from vesin import NeighborList` at module scope, and upstream's
# `python_files = ["*.py"]` makes that file collectable, so without vesin half
# that suite cannot even be collected.  ../nvalchemi-toolkit-ops skips about
# sixty tests with "`vesin` required for consistency checks" — the ones that
# check its own neighbour lists against an independent implementation, which is
# the only thing in that suite doing so.  Internal, not re-exported.
let
  # gpulite, which vesin's CMakeLists pulls in with FetchContent and links
  # unconditionally — there is no option to build without it.  A second
  # `fetchFromGitHub` rather than a submodule or a network fetch at build time,
  # the same arrangement ../enumlib uses for symlib and for the same reason: a
  # build sandbox has no network, and a hash that cannot be computed offline
  # cannot be checked here at all.
  #
  # The revision is upstream's own pin, read out of `vesin/CMakeLists.txt`:
  #
  #   FetchContent_Declare(
  #       gpulite
  #       GIT_REPOSITORY https://github.com/metatensor/gpu-lite.git
  #       GIT_TAG 6c221167aeca7e113ea6f27e9a2e12391bdb189a # mts-v1.3.0
  #
  # Keep the two in step by hand when vesin moves: nothing checks that this
  # commit is still the one vesin asks for, and CMake will happily build
  # against whichever source directory it is handed.
  gpulite = fetchFromGitHub {
    owner = "metatensor";
    repo = "gpu-lite";
    rev = "6c221167aeca7e113ea6f27e9a2e12391bdb189a";
    hash = "sha256-ZM397eSr6D+OyzQhrhzjNb+2wNKu6iEABrNhKN0HjHI=";
  };
in
buildPythonPackage (finalAttrs: {
  pname = "vesin";
  version = "0.6.1";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "Luthaf";
    repo = "vesin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-0SyqDO0QacQoK3ZROjLSm7RZ2zchle/I3HGpIUHKRRw=";
  };

  # Three distributions share this repository — `vesin`, `vesin-torch` and a
  # Fortran binding — and the C++ library they all wrap sits at the top.  This
  # is the numpy one.  `setup.py` reaches the library at `../../vesin` when
  # there is no vendored `lib/`, which is exactly the layout a checkout has, so
  # the sourceRoot has to leave the rest of the tree in place rather than
  # unpacking this directory alone.
  sourceRoot = "${finalAttrs.src.name}/python/vesin";

  build-system = [ setuptools ];

  # cmake as a program, not as a configure step: `setup.py`'s `cmake_ext` runs
  # it itself, on a different directory, with its own options.  Letting the
  # setup hook run first would configure the Python directory, which has no
  # CMakeLists at all.  Same arrangement as ../sisl.
  nativeBuildInputs = [ cmake ];
  dontUseCmakeConfigure = true;

  # Hand CMake the gpulite source it would otherwise clone, through
  # FetchContent's own override for exactly this case.  One line rather than a
  # patch because `cmake_options` is a plain Python list and the items may share
  # a line.
  #
  # `FETCHCONTENT_FULLY_DISCONNECTED` is the belt to that braces: with it on,
  # any *other* FetchContent dependency that appears in a later version fails
  # loudly at configure time instead of attempting a clone that a build sandbox
  # would refuse for reasons of its own.
  postPatch = ''
    substituteInPlace setup.py \
      --replace-fail \
        '"-DBUILD_SHARED_LIBS=ON",' \
        '"-DBUILD_SHARED_LIBS=ON", "-DFETCHCONTENT_SOURCE_DIR_GPULITE=${gpulite}", "-DFETCHCONTENT_FULLY_DISCONNECTED=ON",'
  '';

  dependencies = [ numpy ];

  # ase for `tests/_utils.py` and the three modules that read `tests/data/*.xyz`
  # through `ase.io`, and torch because `test_torch.py` passes torch tensors
  # through the same numpy `NeighborList` — that is the interop path
  # ../torch-pme and ../nvalchemi-toolkit-ops both use, so it is worth covering
  # here rather than only downstream.
  #
  # `test_cupy.py` and `test_gpu_consistency.py` importorskip cupy, which
  # nixpkgs does not carry, and `test_metatomic.py` importorskips metatomic,
  # which it does not either.  All three skip themselves cleanly, so the whole
  # directory can run.
  #
  # pytest-timeout is upstream's — `tox.ini` lists it in three environments —
  # and `tests/test_fork.py` carries the one `@pytest.mark.timeout(10)` that
  # needs it, on a test that forks a process while a neighbour list is live.
  # Without the plugin the mark is unknown, and upstream's
  # `filterwarnings = ["error"]` promotes `PytestUnknownMarkWarning` to a
  # collection error, which stops the whole run rather than that module.  Its
  # absence therefore costs 364 tests, not one.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    pytest-timeout
    torch
  ];

  # The source tree's `vesin/` shadows the installed package, and here that is
  # fatal rather than merely wrong: the shared library is built into
  # `build/lib.linux-*/vesin/lib/libvesin.so` and installed from there, so the
  # source copy is a Python package with no library under it at all.
  # `vesin/__init__.py` calls `get_library()` at import, and every one of the
  # five test modules dies at collection with
  #
  #   ImportError: Could not find vesin shared library at
  #   /build/source/python/vesin/vesin/lib/libvesin.so
  #
  # Removing the source copy makes the import resolve to the installed one.
  # `tests/` is a sibling and reads its data through `__file__`, so nothing else
  # moves.  Same trap as ../sella and ../wignernj — and loud here, as it is in
  # sella, because the package reaches its extension on any import at all.
  preCheck = ''
    rm -rf vesin
  '';

  pythonImportsCheck = [ "vesin" ];

  # Read by ../../scripts/update-universe.nix.  Same shape as ../enumlib's
  # symlib: a separate repository vendored at a fixed rev, on its own cadence,
  # so a bump here does not touch it and this package is not manual.
  passthru.updatePolicy.secondary = [
    {
      name = "gpulite";
      mode = "pinned";
      source = "github:metatensor/gpu-lite";
      version = "6c221167aeca7e113ea6f27e9a2e12391bdb189a";
      reason = "vendored GPU backend, pinned to the rev upstream's build expects";
    }
  ];

  meta = {
    description = "Computing neighbor lists for atomistic systems";
    homepage = "https://github.com/Luthaf/vesin";
    changelog = "https://github.com/Luthaf/vesin/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
