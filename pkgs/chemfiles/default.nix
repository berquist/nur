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

  # Compression backends.  chemfiles vendors all three under external/ as
  # tarballs and builds them itself unless told otherwise; the CHFL_SYSTEM_*
  # options below point it at nixpkgs' copies instead, so that a security fix in
  # zlib is not silently missed by a statically vendored duplicate.
  bzip2,
  xz,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "chemfiles";
  version = "0.11.0-rc1";

  # The tag rather than HEAD, which declares 0.12.0-dev.  0.11.0-rc1 is what the
  # chemfiles.py 0.10.4 submodule pins, so it is the pairing upstream tests, and
  # it satisfies that binding's `find_package(chemfiles CONFIG QUIET 0.10)`.
  src = fetchFromGitHub {
    owner = "chemfiles";
    repo = "chemfiles";
    tag = finalAttrs.version;
    hash = "sha256-hu9sB2onaf8BA0TnCWI20xkgJ2cF8hlAwxfOHR1MS2E=";
  };

  nativeBuildInputs = [ cmake ];

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

    # Left at upstream's default, and deliberately so — see below.
    (lib.cmakeBool "CHFL_BUILD_TESTS" false)
  ];

  # No test suite is run, and unlike a bare `doCheck = false` the reason is
  # structural rather than a shrug: tests/CMakeLists.txt begins with a
  # `file(DOWNLOAD ...)` of https://github.com/chemfiles/tests-data at a pinned
  # commit (7610e0ba23bd8b03a4f74b039f8fe5f6b0a4873a), at *configure* time.  A
  # Nix builder has no network, so enabling CHFL_BUILD_TESTS fails at cmake
  # rather than at ctest.
  #
  # The fix is to supply the data rather than to skip the suite: add
  # chemfiles/tests-data as a second fetchFromGitHub, unpack it to
  # `<builddir>/tests/data`, and `touch` the marker file named after that commit
  # — the download is guarded by `if(NOT EXISTS .../data/${TESTS_DATA_GIT})`, so
  # a pre-placed tree short-circuits it. That is a one-clone change and worth
  # doing; it is left out here only because the hash cannot be computed without
  # the clone.
  #
  # In the meantime ../chemfiles-python's suite is not nothing: it drives this
  # library through the C API for every format it touches.

  meta = {
    description = "Library for reading and writing chemistry trajectory files";
    homepage = "https://chemfiles.org";
    changelog = "https://github.com/chemfiles/chemfiles/blob/${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
