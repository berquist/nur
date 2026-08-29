{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  wheel,

  # dependencies
  networkx,
  numpy,
  rdkit,

  # tests
  pytestCheckHook,
  scipy,
}:

buildPythonPackage {
  pname = "xyzgraph";
  # 1.6.14, not the v1.6.8 that `git describe` reports 24 commits back:
  # pyproject.toml on this commit declares 1.6.14, and it is a static `version`
  # field rather than anything dynamic, so the source is unambiguous.
  version = "1.6.14-unstable-2026-07-19";
  pyproject = true;

  # From git rather than PyPI because the tests are the point: ../graphrc and
  # ../xyzrender both build on this, so a silent regression here surfaces two
  # packages later.  Sixteen test modules and their reference .json/.out
  # fixtures are in the checkout.
  src = fetchFromGitHub {
    owner = "aligfellow";
    repo = "xyzgraph";
    rev = "20255a717d46cb2dac7d13ba13b6054bb37fde84";
    hash = "sha256-xxaFF38zCuEYoOiUR4z9XPUF4pix1cbbhacjx40+FZw=";
  };

  build-system = [
    setuptools
    wheel
  ];

  dependencies = [
    networkx
    numpy
    rdkit
  ];

  # scipy is the `rdkit-tm` extra.  The other half of that extra is `xyz2mol_tm`,
  # which upstream installs straight from a git URL and nixpkgs does not carry —
  # so test_graph_builders_rdkit_tm.py cannot fully run either way.  scipy is
  # supplied anyway because it is cheap and because without it that module
  # fails on the wrong import, which would hide the xyz2mol_tm one.
  nativeCheckInputs = [
    pytestCheckHook
    scipy
  ];

  pythonImportsCheck = [
    "xyzgraph"
    "xyzgraph.cli"
  ];

  meta = {
    description = "Molecular graph construction from Cartesian coordinates";
    homepage = "https://github.com/aligfellow/xyzgraph";
    license = lib.licenses.mit;
    mainProgram = "xyzgraph";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
