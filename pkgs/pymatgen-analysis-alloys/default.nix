{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  pymatgen,
  shapely,

  # tests
  pytestCheckHook,
}:

# Pymatgen add-on for alloy systems: a fourth distribution in the `pymatgen/`
# namespace, installing into `pymatgen/analysis/alloys/`.  `emmet-core` reaches
# its `AlloyPair`/`AlloySystem` through the lazy `emmet.core.io.pymatgen` layer,
# and its own `tests/io/test_pymatgen.py` asserts every add-on import resolves.
# One of atomate2's follow-on targets — see "Deferred packaging" in
# ../../AGENTS.md.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-analysis-alloys";
  version = "0.0.9";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pymatgen-analysis-alloys";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EGS4TMj9ImFt03Y2nHYoQuSSCyPnoDqz/6DtrJwayEY=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository, the same
  # hole ../maggma falls into.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    pymatgen
    shapely
  ];

  # `[tool.pytest.ini_options] testpaths` points at `pymatgen/analysis/alloys/
  # tests`, which ships inside the package; the fixtures are the `*.json` files
  # beside them, resolved relative to the test file, so nothing to set up.
  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "pymatgen.analysis.alloys" ];

  meta = {
    description = "Pymatgen add-on package for alloy systems";
    homepage = "https://github.com/materialsproject/pymatgen-analysis-alloys";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
