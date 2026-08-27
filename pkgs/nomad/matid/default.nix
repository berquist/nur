{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  pybind11,
  ase,
  networkx,
  numpy,
  scikit-learn,
  spglib,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "matid";
  version = "2.1.6";
  pyproject = true;

  # From GitHub rather than the sdist: matid is a pybind11 extension and the
  # sdist ships no tests, so a from-sdist build would prove only that the C++
  # compiles, not that it computes anything.
  src = fetchFromGitHub {
    owner = "nomad-coe";
    repo = "matid";
    tag = "v${version}";
    hash = "sha256-u2ci7loTnU5a1CtJGfN/chqVw8aAXL8rTqYsqIRFz7Q=";
  };

  build-system = [
    setuptools
    # pybind11 is pinned to 2.13.x for the whole nomadPython set — see
    # ../python-overrides.nix.  matid's setup.py compiles with -std=c++11, and
    # pybind11 3.0 requires C++17.
    pybind11
  ];

  dependencies = [
    ase
    networkx
    numpy
    scikit-learn
    spglib
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # classificationtests.py / symmetrytests.py are unittest modules that pytest
  # does not collect by default (upstream drives them from tests/testrunner.py,
  # which also runs the performance suite).  test_geometry.py and the clustering
  # and symmetry directories are the collectible part, and they are what
  # exercises the compiled extension.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "matid"
    "matid.ext"
  ];

  meta = {
    description = "Identification and analysis of atomistic system geometry";
    homepage = "https://github.com/nomad-coe/matid";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
