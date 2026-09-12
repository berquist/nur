{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  mp-pyrho,
  numpy,
  pymatgen-core,
  scikit-image,

  # tests
  pytestCheckHook,
  ase,
  dscribe,
  matplotlib,
}:

# Pymatgen extension for point-defect analysis: a distribution in the
# `pymatgen/` namespace, installing into `pymatgen/analysis/defects/`.
# `emmet-core`'s defects schema and its `tests/io/test_pymatgen.py` reach it
# through the lazy `emmet.core.io.pymatgen` layer.  One of atomate2's follow-on
# targets — see "Deferred packaging" in ../../AGENTS.md.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-analysis-defects";
  version = "2026.3.20-unstable-2026-07-19";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v2026.3.20 tag, four behind it: `6f35553`
  # "Refactor to only require `pymatgen-core`" is exactly the change that lets
  # this sit on the 2026 split rather than pulling the full `pymatgen`, and
  # `dd867f7` fixes a sign error in the EFNV finite-size correction.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pymatgen-analysis-defects";
    rev = "6f355530a7a719428048d0f2d249b52ff4ac3eb7";
    hash = "sha256-k1iHOPbZWvZ/4ka8mlso1y59liix9EEtlCb/Krside0=";
  };

  # versioningit's `method = "git"` wants a repository fetchFromGitHub does not
  # provide; the top-level `default-version` is the fallback it uses for any
  # error during version calculation, and upstream declares only the `vcs`
  # sub-table, so this inserts the parent ahead of it.  See ../qtoolkit for the
  # full account.  The `-unstable-` suffix is not PEP 440, so only the part
  # before the first dash goes in.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${lib.head (lib.splitString "-" finalAttrs.version)}"

    [tool.versioningit.vcs]'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    mp-pyrho
    numpy
    pymatgen-core
    scikit-image
  ];

  # The first build ran 38 passed / 8 failed / 11 errors.  All were missing
  # optional dependencies:
  #
  #   - dscribe (the `finder` extra) — ~15 tests use `DefectSiteFinder`, which
  #     raises `ImportError` rather than skipping.  In nixpkgs, so a check input.
  #   - ase — one supercell test.  Not upstream's dependency, but in nixpkgs.
  #   - vise / pydefect (the `optional` extra) — two `test_kumagai*` regression
  #     tests.  pydefect is a large DFT-workflow package tree of its own; the
  #     kumagai module already guards on `__has_pydefect__`, so these two are
  #     deselected rather than pulling that in.  Clone `pydefect` if the EFNV
  #     correction needs coverage here.
  #
  # matplotlib because tests/conftest.py imports `matplotlib.pyplot` at module
  # scope.  The 264 MB `test_files/` ships in `tests/` and is resolved relative
  # to the test file.  nbmake (notebook tests) is left out — the notebooks are
  # documentation.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    dscribe
    matplotlib
  ];

  # By node id rather than `disabledTests` (`-k`), which for the kumagai entries
  # would also catch `test_kumagai_missing` — the one that checks the
  # no-pydefect guard and must still run.
  pytestFlags = [
    "--deselect=tests/test_corrections.py::test_kumagai"
    "--deselect=tests/test_corrections.py::test_kumagai_vacancy"
    # `plot_formation_energy_diagrams` is deprecated (upstream is moving
    # plotting to `pymatgen.analysis.defects.plotting`, which is tested
    # separately and passes) and calls `axis.legend(handles=[], labels=[])`,
    # which matplotlib 3.11 turns into `ValueError: not enough values to
    # unpack`.  The replacement path is covered by tests/plotting/.
    "--deselect=tests/test_thermo.py::test_plotter"
  ];

  pythonImportsCheck = [
    "pymatgen.analysis.defects"
    "pymatgen.analysis.defects.core"
    "pymatgen.analysis.defects.thermo"
  ];

  meta = {
    description = "Pymatgen extension for defects analysis";
    homepage = "https://github.com/materialsproject/pymatgen-analysis-defects";
    license = lib.licenses.bsd3Lbnl;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
