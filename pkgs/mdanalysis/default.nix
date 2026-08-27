{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  numpy,
  setuptools,
  wheel,

  # dependencies
  filelock,
  griddataformats,
  joblib,
  matplotlib,
  mda-xdrlib,
  mmtf-python,
  packaging,
  scipy,
  threadpoolctl,
  tqdm,
}:

buildPythonPackage rec {
  pname = "mdanalysis";
  version = "2.11.0.dev0-unstable-2026-08-10";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MDAnalysis";
    repo = "mdanalysis";
    rev = "c882e5cd20d461e5b4db7d25bae150a88956aea5";
    hash = "sha256-SdLZf6Pe21XLtx+nw2PXA3x6oVIlTdqfyT+PKaY4If4=";
  };

  # The repository is a monorepo holding two distributions: `package/` is
  # MDAnalysis itself and `testsuite/` is MDAnalysisTests, which is where every
  # test lives.  Only the first is built here — see the note on checks below.
  sourceRoot = "${src.name}/package";

  build-system = [
    cython
    numpy
    setuptools
    wheel
  ];

  dependencies = [
    filelock
    griddataformats
    joblib
    matplotlib
    mda-xdrlib
    mmtf-python
    packaging
    scipy
    threadpoolctl
    tqdm
  ];

  # No test suite is run, and this is not a `doCheck = false` in disguise: the
  # MDAnalysis distribution genuinely ships no tests.  They are a separate
  # distribution, MDAnalysisTests, whose 70 MB of trajectory fixtures live in
  # the sibling `testsuite/` directory of the same repository.  Packaging that
  # is worth doing on its own terms; nothing here depends on it, and QMzyme —
  # the only consumer in this repo — carries its own suite.
  #
  # The import check below is doing real work despite that.  This package has
  # some thirty compiled Cython extensions, and importing the four subpackages
  # that dominate them is what catches a build where cythonize silently
  # produced nothing.
  pythonImportsCheck = [
    "MDAnalysis"
    "MDAnalysis.analysis"
    "MDAnalysis.coordinates"
    "MDAnalysis.lib"
    "MDAnalysis.topology"
  ];

  meta = {
    description = "Object-oriented toolkit to analyze molecular dynamics trajectories";
    homepage = "https://www.mdanalysis.org";
    changelog = "https://github.com/MDAnalysis/mdanalysis/blob/develop/package/CHANGELOG";
    license = lib.licenses.lgpl3Plus;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
