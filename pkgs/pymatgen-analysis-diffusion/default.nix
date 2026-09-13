{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  joblib,
  numpy,
  pymatgen,
  seaborn,

  # tests
  pytestCheckHook,
  maggma,
  matplotlib,
}:

# Pymatgen add-on for diffusion analysis (van Hove, RDF, NEB path finding): a
# distribution in the `pymatgen/` namespace, installing into
# `pymatgen/analysis/diffusion/`.  `emmet-core`'s mobility schema and its
# `tests/io/test_pymatgen.py` reach its `MigrationGraph` through the lazy
# `emmet.core.io.pymatgen` layer.  atomate2's `approxneb` extra wants it too —
# see "Deferred packaging" in ../../AGENTS.md.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-analysis-diffusion";
  version = "2025.11.14";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsvirtuallab";
    repo = "pymatgen-analysis-diffusion";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QvjMxIUz0yay+Q4w2ppHc5Ss5NWD37sUd5FEgfBijjA=";
  };

  # pymatgen renamed `StructureGraph.with_local_env_strategy` to
  # `from_local_env_strategy` (the old name is gone, not deprecated), and
  # `full_path_mapper.py` still calls the old one at module-import scope — so
  # `MigrationGraph.with_distance` blows up during test collection, before a
  # single test runs.  Signature and behaviour are unchanged; this is a pure
  # rename.  Upstream's master has not caught up.
  #
  # The second hunk is a stale reference string: newer pymatgen writes `NELECT`
  # into the INCAR as a float (`576.0`), and `test_incar_user_setting` still
  # expects `576`.  Cosmetic, and updating the expected value keeps the rest of
  # that INCAR assertion live.
  postPatch = ''
        substituteInPlace src/pymatgen/analysis/diffusion/neb/full_path_mapper.py \
          --replace-fail \
            'StructureGraph.with_local_env_strategy(' \
            'StructureGraph.from_local_env_strategy('

        substituteInPlace tests/pymatgen/analysis/diffusion/neb/test_io.py \
          --replace-fail \
            'NELECT = 576
    NELM = 200' \
            'NELECT = 576.0
    NELM = 200'
  '';

  # The version is a plain string in pyproject.toml, so setuptools needs no help
  # here — unlike the other add-ons.
  build-system = [ setuptools ];

  dependencies = [
    ase
    joblib
    numpy
    pymatgen
    seaborn
  ];

  # maggma because several test modules import `maggma.stores.JSONStore` to load
  # their fixtures; matplotlib because `aimd/van_hove` is plotted in tests.
  nativeCheckInputs = [
    pytestCheckHook
    maggma
    matplotlib
  ];

  pythonImportsCheck = [
    "pymatgen.analysis.diffusion"
    "pymatgen.analysis.diffusion.neb.full_path_mapper"
  ];

  meta = {
    description = "Pymatgen add-on for diffusion analysis";
    homepage = "https://github.com/materialsvirtuallab/pymatgen-analysis-diffusion";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
