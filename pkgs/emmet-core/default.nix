{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  blake3,
  inflect,
  monty,
  pubchempy,
  pybtex,
  pydantic,
  pydantic-settings,
  pymatgen,
  pymatgen-io-validation,
  typing-extensions,

  # tests
  pytestCheckHook,
  pytest-xdist,
  custodian,
  lobsterpy,
  openbabel-bindings,
  optimade,
  pyarrow,
  pymatgen-analysis-alloys,
  pymatgen-analysis-defects,
  pymatgen-analysis-diffusion,
  pymongo,
}:

# The schema layer of the Materials Project stack: pydantic models for VASP and
# Q-Chem tasks, materials documents, thermo, elasticity, phonons and the rest.
# `atomate2` and `quacc` both depend on it, and it was the last gap in the
# chain — see "Deferred packaging" in ../../AGENTS.md.
#
# One package inside the `materialsproject/emmet` monorepo, at `emmet-core/`,
# which is why `src` is the whole repository and `sourceRoot` picks the
# subdirectory out.  `emmet-api`, `emmet-builders` and the two CLIs are the
# other members and are not packaged.
buildPythonPackage (finalAttrs: {
  pname = "emmet-core";
  version = "0.87.2";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "emmet";
    tag = "v${finalAttrs.version}";
    hash = "sha256-0tGOkIcT3cgdSyQF/VPwiNHMXK9mcndTWfAj5NGKKrA=";
  };

  sourceRoot = "${finalAttrs.src.name}/emmet-core";

  # setuptools_scm reads the version from git — and with `root = ".."` it looks
  # for the repository one level above `emmet-core/`, i.e. at the monorepo root,
  # which fetchFromGitHub hands over without a `.git`.  The pretend version is
  # what the project's own CI sets (`git describe --tags --abbrev=0 | sed
  # 's/^v//'`), derived from `version` here so the two cannot drift.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `include = ["emmet.core"]` alone keeps only the top package: setuptools'
  # package finder matches `include` patterns with `fnmatchcase`, and
  # `emmet.core.vasp` does not match `emmet.core`.  Upstream's released wheels
  # work, so setuptools >= 80 may already walk into a named parent — but spelling
  # the subpackage glob out costs nothing and removes the doubt.  If the build
  # ever shows this is redundant, drop it.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        'include = ["emmet.core"]' \
        'include = ["emmet.core", "emmet.core.*"]'
  '';

  build-system = [
    setuptools
    setuptools-scm
  ];

  # `pybtex~=0.24` excludes 0.25, which is what the channels here carry.  emmet
  # uses pybtex only through `emmet.core.provenance` (BibTeX round-tripping), and
  # nothing in 0.25 changed that surface.
  pythonRelaxDeps = [ "pybtex" ];

  dependencies = [
    blake3
    inflect
    monty
    pubchempy
    pybtex
    pydantic
    pydantic-settings
    pymatgen
    pymatgen-io-validation
    typing-extensions
  ];

  # The first build ran 518 passed / 13 failed / 4 errors; the last, 792 passed
  # / 4 failed (the four fixed by the `preCheck` chmod below).  Every failure
  # along the way was a missing optional dependency, a network call, or a
  # read-only path — not an emmet bug:
  #
  #   - the three pymatgen-analysis-{alloys,defects,diffusion} add-ons, which
  #     `tests/io/test_pymatgen.py::test_imports` walks unconditionally and
  #     `test_defects.py` / `test_migrationgraph.py` import at module scope.
  #     Packaged, and check inputs here.
  #   - pyarrow, which emmet gates on with `ARROW_COMPATIBLE`.  Its absence left
  #     `test_thermo.py` referencing an unimported name and `test_trajectory.py`
  #     raising outright.  In nixpkgs, so a check input.
  #   - three tests that reach the network (`test_from_url` hits
  #     raw.githubusercontent.com, two robocrys molecule-name tests hit PubChem).
  #     Deselected below — nothing to package.
  #
  # `optimade` and `lobsterpy` are now packaged too, so `test_optimade` and
  # `test_lobster` run rather than skip.  `matgl` is deliberately left out: its
  # `M3GNetSimilarity` loads a pretrained model over the network, which
  # `test_similarity` would then hit — it stays a clean `skipif matgl is None`.
  #
  # custodian is a real import in `emmet.core.qc_tasks`, and bson (pymongo) and
  # openbabel in the qchem test helpers.  pytest-xdist because the suite is
  # large and nixpkgs' hook passes --numprocesses when it is present.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    custodian
    lobsterpy
    openbabel-bindings
    optimade
    pyarrow
    pymatgen-analysis-alloys
    pymatgen-analysis-defects
    pymatgen-analysis-diffusion
    pymongo
  ];

  # The project's CI runs `pytest emmet-core/tests`; without the path pytest
  # also collects `dev_scripts/gen_api_field_test.py`, which is a generator
  # script rather than a test and errors on import.
  enabledTestPaths = [ "tests" ];

  disabledTests = [
    # Reach the network — raw.githubusercontent.com and PubChem respectively.
    "test_from_url"
    "test_get_name_from_molecule_graph"
    "test_get_name_from_pubchem"
  ];

  # The test-file resolver in `emmet.core.testing_utils` walks three parents up
  # from the *installed* `emmet/core` and appends `test_files`.  pytest puts
  # `emmet-core/` on sys.path (its `tests/` is a package), so `import emmet`
  # resolves to the source tree, and three parents up from
  # `source/emmet-core/emmet/core` is `source/`, where the monorepo's 36 MB of
  # `test_files/` actually is.  That is why `sourceRoot` keeps the whole repo.
  #
  # `sourceRoot` also means unpackPhase only makes `emmet-core/` writable, not
  # its `../test_files` sibling — and `test_lobster.py` with
  # `add_coxxcar_to_task_document=True` writes a parsed file back into
  # `test_files/lobster/mp-2534/`.  Widen the permissions so those four cases
  # can run.
  preCheck = ''
    chmod -R u+w "$(realpath ../test_files)"
  '';

  pythonImportsCheck = [
    "emmet.core"
    "emmet.core.structure"
    "emmet.core.symmetry"
    "emmet.core.tasks"
  ];

  meta = {
    description = "Core Emmet library: schemas for the Materials Project";
    homepage = "https://github.com/materialsproject/emmet";
    changelog = "https://github.com/materialsproject/emmet/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.bsd3Lbnl;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
