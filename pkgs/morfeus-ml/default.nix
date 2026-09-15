{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  fire,
  numpy,
  packaging,
  scipy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  # The distribution is `morfeus-ml`; the import name is `morfeus`.  The
  # distribution name is what has to be right here, and not only for aqme's
  # `morfeus-ml==0.8.0` bound: morfeus/__init__.py ends with
  # `__version__ = metadata.version("morfeus-ml")`, so an installed dist under
  # any other name makes importing the package raise PackageNotFoundError.
  pname = "morfeus-ml";
  version = "0.8.0-unstable-2026-09-02";
  pyproject = true;

  # Fifteen commits past the v0.8.0 tag, whose `setup.py` still says 0.8.0.
  src = fetchFromGitHub {
    owner = "digital-chemistry-laboratory";
    repo = "morfeus";
    rev = "e5dacf9e0519249ea0ce22f113b490da18846441";
    hash = "sha256-AWp7bb+eQpA4il5y4wtMw6PT8/5oD4QaDJg6GMwpSZc=";
  };

  build-system = [ setuptools ];

  # Exactly `install_requires` from setup.py.  The three optional families are
  # deliberately absent, and none of them is a hidden hard dependency:
  # morfeus/utils.py's `requires_dependency` decorator turns each into a runtime
  # error only on the code path that needs it.
  #
  #   libconeangle — not in nixpkgs.  cone_angle.py catches the ImportError and
  #     falls back to method="internal", which is what the one cone-angle test
  #     that survives the marker filter below exercises anyway.
  #   pyvista, pyvistaqt, pymeshfix, vtk — Dispersion's surface plotting only.
  #   qcelemental, qcengine — morfeus/qc.py, an optional QC-program interface.
  dependencies = [
    fire
    numpy
    packaging
    scipy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # No extra check inputs and no disabledTests: upstream's own
  # `addopts = "-m 'not (benchmark or xtb)'"` already deselects both the
  # reference-data benchmarks and everything that shells out to xtb, which is
  # the whole of what would otherwise need a program or network.
  pythonImportsCheck = [ "morfeus" ];

  meta = {
    description = "Molecular features for machine learning — steric descriptors and more";
    homepage = "https://github.com/digital-chemistry-laboratory/morfeus";
    changelog = "https://github.com/digital-chemistry-laboratory/morfeus/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "morfeus";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
