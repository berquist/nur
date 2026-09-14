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
  imageio,
  matplotlib,
  networkx,
  opencv4,
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

  # The single-channel EXR assertion in `test_read_image_Imageio` cannot hold
  # under any EXR backend installable here — one of the three imageio will
  # consider is a library nixpkgs removed for vulnerabilities, one is an ffmpeg
  # decoder that is not implemented, and the third always returns three
  # channels.  See the patch's header, which is the long version of the
  # `opencv4` note below, and note that the same assertion still runs through
  # OpenImageIO in `TestReadImage`.
  patches = [ ./imageio-single-channel-exr.patch ];

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
  # opencv4 is imageio's EXR backend, and it is the *third* candidate rather
  # than the first two for reasons worth writing down, because the obvious two
  # both fail.  imageio's priority list for `.exr` is
  # `["EXR-FI", "pyav", "opencv"]`.  `EXR-FI` downloads a FreeImage binary on
  # first use, which no build here can do.  `pyav` was tried and gets further —
  # imageio selects it, so `Could not find a backend` is gone — and then
  # ffmpeg's EXR decoder gives up inside `avcodec_send_packet()` with
  # `av.error.PatchWelcomeError: Not yet implemented in FFmpeg`.
  #
  # **So `av` must not be installed at all, not merely joined by opencv4.**
  # That priority list is consulted once, when the plugin is chosen; the pyav
  # failure happens later, at `read()`, with no fall-through to the next
  # candidate.  Leaving av in the closure would keep pyav winning the choice
  # and keep it failing the read.
  #
  # nixpkgs' opencv4 takes `enableEXR ? !isDarwin` and passes `WITH_OPENEXR=ON`,
  # so the codec is compiled in.  OpenCV then gates it behind an environment
  # variable at run time — a deliberate hardening, added because the EXR
  # decoder had been a source of CVEs — which is what `preCheck` sets.
  #
  # openimageio is the *retargeted* one from ../../overlays/default.nix, not
  # nixpkgs' attribute: nixpkgs builds its binding against python3, which is
  # 3.14 here, so the module installs where no 3.13 set will look.  The overlay
  # passes the `out` output explicitly, because the default output of that
  # derivation is `bin`.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    imageio
    matplotlib
    networkx
    opencv4
    openimageio
    pandas
    scipy
    tqdm
    xxhash
  ];

  # OpenCV compiles the OpenEXR codec in but refuses to use it unless this is
  # set; without it `imread` returns None and imageio reports a read failure
  # rather than a missing codec, which is a confusing way to learn this.
  preCheck = ''
    export OPENCV_IO_ENABLE_OPENEXR=1
  '';

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
