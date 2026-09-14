{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  numpy,

  # tests
  pytestCheckHook,
  pytest-xdist,
  av,
  imageio,
  matplotlib,
  networkx,
  openimageio,
  pandas,
  scipy,
  tqdm,
  xxhash,
}:

buildPythonPackage {
  # The distribution is `colour-science`; the import name is `colour`.  Not to
  # be confused with nixpkgs' `colour` (vaab/colour 0.1.5), which is a small
  # colour-name utility that happens to claim the same import name — the two
  # cannot be installed into one environment.
  pname = "colour-science";
  version = "0.4.7-unstable-2026-08-16";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "colour-science";
    repo = "colour";
    rev = "b6b2a95ac80123ace9cc929b041bfad823ce6823";
    hash = "sha256-LsQ7zhW6Ij0oVXnq9rL1Ocx4kLEI5tkRA6q/9cOjx5o=";
  };

  build-system = [ hatchling ];

  # numpy is the only hard requirement upstream declares, and that is accurate:
  # everything in the `optional` extra is imported lazily, behind
  # colour.utilities.required.
  dependencies = [ numpy ];

  # ...but the test suite is not so restrained, and exercises those lazy paths.
  # These are the members of upstream's `optional` extra that nixpkgs carries.
  #
  # **They do not skip themselves when missing.**  An earlier note here claimed
  # the members nixpkgs lacks gate tests that skip; they do not — fourteen
  # OpenImageIO tests failed outright with `ImportError`, because
  # `colour.utilities.required` raises rather than skips.  Anything upstream
  # lists and this suite touches has to be present.
  #
  # pytest-xdist is not optional here: upstream's own
  # `addopts = "-n auto --dist=loadscope"` makes pytest fail on an unknown
  # option without it.
  #
  # xxhash is not a test-only nicety either, and this is the one entry worth
  # reading twice.  `colour/utilities/common.py` picks `int_digest` at *import*
  # time: `xxhash.xxh3_64_intdigest` when xxhash is installed, and the builtin
  # `hash` when it is not.  `TestIntDigest` asserts the xxh3 digest of "Foo"
  # (7467386374397815550) and got -8220717926372737780, which is what the
  # builtin returns.
  #
  # The builtin is the wrong function rather than an unstable one *here*:
  # nixpkgs' Python setup hook exports `PYTHONHASHSEED=0`, so inside a build the
  # fallback is perfectly reproducible and simply disagrees with upstream's
  # reference value.  Outside a build there is no such export and `hash` is
  # salted per process, which makes every `Signal.__hash__` and every
  # tristimulus cache key change between runs.  So this is a check input,
  # matching upstream's `optional` extra, but a consumer who wants digests that
  # survive a restart wants xxhash installed as well.
  #
  # `av` is imageio's EXR backend.  imageio's own priority list for `.exr` is
  # `["EXR-FI", "pyav", "opencv"]`, and the first of those downloads a
  # FreeImage binary on first use, which no build here can do — so
  # `read_image_Imageio` had no backend at all and `TestReadImageImageio` died
  # on `Could not find a backend`.  If pyav turns out not to decode this file,
  # the remaining option is `opencv4` with `OPENCV_IO_ENABLE_OPENEXR=1`, which
  # is both a larger closure and an env var OpenCV added deliberately.
  #
  # openimageio is the *retargeted* one from ../../overlays/default.nix, not
  # nixpkgs' attribute: nixpkgs builds its binding against python3, which is
  # 3.14 here, so the module installs where no 3.13 set will look.  The overlay
  # passes the `out` output explicitly, because the default output of that
  # derivation is `bin`.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    av
    imageio
    matplotlib
    networkx
    openimageio
    pandas
    scipy
    tqdm
    xxhash
  ];

  # `TestDownloadUrl::test_download_url` fetches a real URL and fails on name
  # resolution.  Nothing local can stand in for it, and what it covers is
  # urllib, so this is the one genuine deselection in this suite.
  disabledTests = [ "test_download_url" ];

  # A large numerical suite pinned to reference values.  If it fails on the
  # locked nixpkgs' numpy, that is tolerance drift and the fix is a
  # `disabledTests` entry naming the case — not switching the suite off.
  pythonImportsCheck = [
    "colour"
    "colour.colorimetry"
    "colour.models"
  ];

  meta = {
    description = "Colour Science for Python — algorithms and datasets for colour science";
    homepage = "https://www.colour-science.org";
    changelog = "https://github.com/colour-science/colour/releases";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
