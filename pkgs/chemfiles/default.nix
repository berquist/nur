# The chemfiles C++ library.
#
# Not a Python package: this is the shared library that ../chemfiles-python
# binds to.  It is packaged in its own right because nixpkgs has no chemfiles at
# all, and because the binding is explicitly designed to load an external copy —
# see the `find_package` note in ../chemfiles-python/default.nix.
{
  lib,
  stdenv,
  fetchFromGitHub,

  cmake,

  # Only for the test suite, and only as an interpreter: tests/CMakeLists.txt
  # ends with `find_package(Python REQUIRED)` and registers tests/lints/*.py —
  # five source-linting scripts that check the C API docs, the error messages,
  # the public headers and so on — as ctest cases.  REQUIRED, so without this
  # the *configure* step fails outright:
  #
  #   CMake Error at .../FindPackageHandleStandardArgs.cmake:290 (message):
  #     Could NOT find Python (missing: Python_EXECUTABLE Interpreter)
  #   Call Stack (most recent call first):
  #     tests/CMakeLists.txt:203 (find_package)
  #
  # A native build input rather than a check input, because cmake resolves it at
  # configure time, well before checkPhase.
  python3,

  # Compression backends.  chemfiles vendors all three under external/ as
  # tarballs and builds them itself unless told otherwise; the CHFL_SYSTEM_*
  # options below point it at nixpkgs' copies instead, so that a security fix in
  # zlib is not silently missed by a statically vendored duplicate.
  bzip2,
  xz,
  zlib,
}:

let
  # Pinned by tests/CMakeLists.txt itself, in TESTS_DATA_GIT on its first line.
  # Bump this in lockstep with `version`, and expect the suite to fail loudly if
  # they disagree — the marker file the download guard looks for is named after
  # this exact string.
  testsDataRev = "7610e0ba23bd8b03a4f74b039f8fe5f6b0a4873a";

  testsData = fetchFromGitHub {
    owner = "chemfiles";
    repo = "tests-data";
    rev = testsDataRev;
    hash = "sha256-aQMASGiWx8esxGF8MN99G/8VOZH8vPTCK9Wsqh7CMAo=";
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "chemfiles";
  version = "0.12.0-dev-unstable-2026-11-19";

  # A fork, until upstream takes the fix.  `set-cpp-std-17` is the 0.11.0-rc1
  # tag, twelve upstream bug-fix commits, and one more that sets
  # `CMAKE_CXX_STANDARD 17` in cmake/CompilerFlags.cmake.  Upstream asks only
  # for `cxx_std_17` through `target_compile_features`, which is a minimum, so
  # CMake adds no `-std=` when the compiler's default is newer.  GCC 16 defaults
  # to C++20, where the bundled fmt checks format strings with consteval, and the
  # runtime format strings in error_fmt.hpp and warnings.hpp stop compiling.
  #
  # Pinned to the commit rather than the branch name, so the hash cannot go
  # stale under it.  The branch is past the tag, so it says 0.12.0-dev;
  # ../chemfiles-python asks for that minor version to match.  Go back to
  # upstream's `chemfiles` owner once the fix is merged there.
  src = fetchFromGitHub {
    owner = "berquist";
    repo = "chemfiles";
    rev = "e8b3c04fa908de2905952a013eae696f6145b285";
    hash = "sha256-GyOt4aD5AwZSQpnBFWmqwiLBXdWz1dGng+wwXY3Hx+0=";
  };

  nativeBuildInputs = [
    cmake
    python3
  ];

  buildInputs = [
    bzip2
    xz
    zlib
  ];

  cmakeFlags = [
    # A shared build is not optional here.  ../chemfiles-python's CMakeLists
    # calls `get_target_property(CHEMFILES_TYPE chemfiles TYPE)` and issues a
    # FATAL_ERROR on anything that is not SHARED_LIBRARY, because the binding
    # loads the library through ctypes at import time.  Upstream defaults this
    # to OFF.
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)

    (lib.cmakeBool "CHFL_SYSTEM_BZIP2" true)
    (lib.cmakeBool "CHFL_SYSTEM_LZMA" true)
    (lib.cmakeBool "CHFL_SYSTEM_ZLIB" true)

    (lib.cmakeBool "CHFL_BUILD_TESTS" true)
  ];

  # The suite runs, and getting there needed one trick.
  #
  # tests/CMakeLists.txt opens with a `file(DOWNLOAD ...)` of
  # chemfiles/tests-data at a pinned commit, at *configure* time — so with no
  # network, enabling CHFL_BUILD_TESTS fails at cmake rather than at ctest.
  # But the download is guarded:
  #
  #   if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/data/${TESTS_DATA_GIT}")
  #
  # and the last thing the unpack does is `touch data/${TESTS_DATA_GIT}`.  So a
  # tree placed at that path with that marker file short-circuits the whole
  # block, and no patching of upstream's CMakeLists is needed.
  #
  # `build/` is nixpkgs' default cmakeBuildDir, and preConfigure runs before
  # cmakeConfigurePhase creates and enters it, so the directory has to be made
  # here rather than assumed.  chmod because the store tree is read-only and
  # some format tests write beside their inputs.
  preConfigure = ''
    mkdir -p build/tests
    cp -r ${testsData} build/tests/data
    chmod -R u+w build/tests/data
    touch build/tests/data/${testsDataRev}
  '';

  # Turning this on is not free: it compiles some 200 test binaries alongside
  # the library, so `just ci-build` pays for it every time this derivation
  # changes.  Worth it — this is the only thing here that exercises the C++ API
  # directly, and ../chemfiles-python only ever reaches it through the C ABI.
  doCheck = true;

  # ctest rather than a `check` target: chemfiles registers its tests with
  # add_test and provides no `make check`, so the generic checkPhase would find
  # nothing to do and report success — the C++ spelling of the same trap
  # ../../AGENTS.md describes for pytest.
  checkPhase = ''
    runHook preCheck

    ctest --output-on-failure -j "$NIX_BUILD_CORES"

    runHook postCheck
  '';

  # Read by ../../scripts/update-universe.nix.  This derivation has a second
  # fetch, and docs/version-updates.md used to write that off as permanently
  # manual.  It is not: `testsDataRev` is pinned by upstream's own
  # tests/CMakeLists.txt, so after a version bump the driver reads the new value
  # out of the new source, rewrites the binding, and lets
  # ../../scripts/refresh-hashes.sh recover the hash from the build's mismatch.
  # That is the whole of what the note above `testsDataRev` asks a human to do.
  passthru.updatePolicy.mode = "pinned";
  passthru.updatePolicy.reason = "a fork commit carrying the C++17 fix; see the note above src";
  passthru.updatePolicy.secondary = [
    {
      name = "testsData";
      mode = "derived";
      revFrom = {
        file = "tests/CMakeLists.txt";
        pattern = "TESTS_DATA_GIT +([0-9a-f]+)";
        binding = "testsDataRev";
      };
      reason = "the test data rev is whatever tests/CMakeLists.txt names at the new version";
    }
  ];

  meta = {
    description = "Library for reading and writing chemistry trajectory files";
    homepage = "https://chemfiles.org";
    changelog = "https://github.com/chemfiles/chemfiles/blob/${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
