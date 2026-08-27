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
  pandas,
  scipy,
  tqdm,
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
  # These are the members of upstream's `optional` extra that nixpkgs carries;
  # the four it does not (onnxruntime, opencolorio, openimageio, trimesh) gate
  # tests that skip themselves when the import fails.
  #
  # pytest-xdist is not optional here: upstream's own
  # `addopts = "-n auto --dist=loadscope"` makes pytest fail on an unknown
  # option without it.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    imageio
    matplotlib
    networkx
    pandas
    scipy
    tqdm
  ];

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
