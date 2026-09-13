{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  matplotlib,
  more-itertools,
  numpy,

  # tests
  pytestCheckHook,
  pytest-mpl,
}:

# matplotlib-label-lines — labels drawn on the lines themselves rather than in a
# legend.  Here for `doped` and `pydefect`, both of which use it for their defect
# formation-energy diagrams, and for nothing else.  Internal, not re-exported.
#
# Distribution `matplotlib-label-lines`, import `labellines`.
buildPythonPackage {
  pname = "matplotlib-label-lines";
  version = "0.8.1-unstable-2026-06-02";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD, 90 commits past v0.8.1 — mostly pre-commit and dependabot churn, but
  # it also carries the matplotlib 3.10 compatibility work, and 3.10 is newer
  # than anything the tag was tested against.
  src = fetchFromGitHub {
    owner = "cphyc";
    repo = "matplotlib-label-lines";
    rev = "aca1ae57f0a280a8ac84c59a75740d2d442d873f";
    hash = "sha256-K4fiH5f9BOqn4hfg53TcRcY9/O2fNRgxIBr8Uv54eVw=";
  };

  build-system = [ hatchling ];

  dependencies = [
    matplotlib
    more-itertools
    numpy
  ];

  # pytest-mpl is needed even though the image comparison is not run.  Twenty-four
  # tests carry its `@pytest.mark.mpl_image_compare` marker, and upstream's
  # `[tool.pytest.ini_options] filterwarnings = ["error"]` turns pytest's
  # unknown-marker warning into a failure — so without the plugin the suite
  # fails on the decorator rather than on anything it tests.
  #
  # The comparison itself needs `--mpl`, which is deliberately not passed: it
  # diffs against the PNGs in `labellines/baseline/`, and those are rendered by
  # one exact matplotlib — upstream's own test extra pins `matplotlib==3.10.8`
  # for the purpose.  Without the flag the plotting code still runs, which is
  # the part that can break; only the pixels go unchecked.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mpl
  ];

  # The suite is one module *inside* the package, and named `test.py` — which
  # pytest's default `python_files` matches neither as `test_*.py` nor as
  # `*_test.py`, so collection finds nothing at all unless it is named here.
  # The same trap ../pgtest has, and ../../AGENTS.md's "sdist-has-no-tests"
  # section describes.
  #
  # It has to be reached through the package rather than as a loose file: its
  # first import is `from .core import labelLine, labelLines`.
  enabledTestPaths = [ "labellines/test.py" ];

  pythonImportsCheck = [
    "labellines"
    "labellines.core"
  ];

  meta = {
    description = "Label matplotlib lines in place of a legend";
    homepage = "https://github.com/cphyc/matplotlib-label-lines";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
