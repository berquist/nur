{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  mrcfile,
  numpy,
  scipy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  # The distribution is `GridDataFormats`; the import name is `gridData`.
  pname = "griddataformats";
  # PEP 440 rather than the usual `-unstable-YYYY-MM-DD`: this string is
  # substituted into versioningit's `default-version` below, and the build fails
  # outright on anything the packaging library cannot parse.  Same in
  # ../mda-xdrlib and ../qmzyme.
  version = "1.2.0.dev20260723";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MDAnalysis";
    repo = "GridDataFormats";
    rev = "8a8f17489e3a699618bcfc15a612c8347ece44b7";
    hash = "sha256-jV/bwaIPsnTJTn4BabbqEXK72DTv9g9lyxYF1W+I9dg=";
  };

  # See ../mda-xdrlib for why the versioningit fallback has to be rewritten.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'default-version = "1+unknown"' 'default-version = "${version}"'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # mrcfile is not optional despite only being used by gridData/mrc.py:
  # gridData/__init__.py does `from . import mrc` unconditionally, so a missing
  # mrcfile makes `import gridData` — and therefore all of MDAnalysis — fail.
  dependencies = [
    mrcfile
    numpy
    scipy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # gridData/tests/test_vdb.py needs OpenVDB's Python bindings, which nixpkgs
  # does not build.  Upstream treats that format as optional — gridData/OpenVDB
  # imports lazily — so this is the one file that cannot run, not a suite-wide
  # problem.
  disabledTestPaths = [ "gridData/tests/test_vdb.py" ];

  pythonImportsCheck = [
    "gridData"
    "gridData.OpenDX"
    "gridData.mrc"
  ];

  meta = {
    description = "Reading and writing of data on regular grids in Python";
    homepage = "https://github.com/MDAnalysis/GridDataFormats";
    changelog = "https://github.com/MDAnalysis/GridDataFormats/blob/master/CHANGELOG";
    license = lib.licenses.lgpl3Plus;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
