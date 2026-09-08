{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,
  hatch-vcs,
  hatch-fancy-pypi-readme,

  # dependencies
  ase,
  ase-db-backends,
  clusterscope,
  e3nn,
  huggingface-hub,
  hydra-core,
  lmdb,
  matplotlib,
  monty,
  numba,
  numpy,
  orjson,
  pandas,
  pyarrow,
  pymatgen,
  pyyaml,
  ray,
  requests,
  scipy,
  setuptools,
  submitit,
  torch,
  torchtnt,
  tqdm,
  wandb,
  websockets,

  # tests
  pytestCheckHook,
  filelock,
  omegaconf,
  scikit-learn,
  syrupy,
}:

# fairchem-core — FAIR Chemistry's machine-learned interatomic potentials and
# the training/inference machinery around them.  `matcalc`'s `fairchem` extra
# and `quacc`'s `mlip` extra both want exactly this one distribution.
# Internal, not re-exported.
#
# It is one package out of a thirteen-distribution monorepo, the same
# arrangement as ../emmet-core.  `quacc[fairchem]` additionally wants
# `fairchem-data-{omat,oc,omol}` out of the same tree; those are not packaged,
# so that extra stays out while `quacc[mlip]` — which asks for `fairchem-core`
# alone, beside the already-packaged ../matcalc and ../rootstock — is reachable.
buildPythonPackage (finalAttrs: {
  pname = "fairchem-core";
  version = "2.22.0";
  pyproject = true;
  __structuredAttrs = true;

  # The monorepo tags each distribution separately, so this is
  # `fairchem_core-2.22.0` rather than a bare version — underscores, because
  # that is how upstream spells the tag.  22.4 MB, nearly all of it source and
  # configs; nothing like ../doped's 873 MB.
  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "fairchem";
    tag = "fairchem_core-${finalAttrs.version}";
    hash = "sha256-v2OxwwaC01I/JI/CnbUstpApcBQyDwTcjMA4XKXUUDw=";
  };

  # `packages/fairchem-core/` holds a pyproject.toml and a single symlink,
  # `src -> ../../src`, which is how the monorepo gives each distribution its
  # own build without moving any code.  fetchFromGitHub preserves the symlink
  # and its target is inside the same unpacked tree, so it resolves from here.
  sourceRoot = "${finalAttrs.src.name}/packages/fairchem-core";

  build-system = [
    hatchling
    hatch-vcs
    hatch-fancy-pypi-readme
  ];

  # hatch-vcs is setuptools-scm underneath, so it takes the same override — and
  # it needs one twice over here: there is no repository to read, and
  # `[tool.hatch.version.raw-options]` points `root` at `../../` with a custom
  # `git_describe_command` matching `fairchem_core-*`, neither of which can work
  # from an unpacked tarball.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # Four upper bounds that the channels here are past, and one that only looks
  # like a problem:
  #
  #   torch `~=2.13.0` against nixpkgs' 2.12.0.  This pin is a wheel-selection
  #   mechanism rather than an API floor — `[tool.uv.sources]` routes torch
  #   through four per-CUDA index URLs and the version pin is what makes that
  #   resolve to one of them.  Nothing in `src/fairchem/core/` branches on
  #   `torch.__version__`.
  #
  #   numpy `<2.5` against 2.5.1 is a defensive upper cap of the usual kind.
  #
  #   lmdb `<=1.7.3` against 2.3.0 is **not**, and relaxing it was a mistake
  #   that is still costing about 43 of this suite's failures.  py-lmdb 2.0.0
  #   added a process-wide registry of open environment paths and made a second
  #   `open()` of one an error (commit 2b26c9f, "Prevent opening the same LMDB
  #   environment twice"); `_open_env_paths` is absent at tags 1.7.3 and 1.8.1
  #   and present at 2.0.0.  fairchem caps exactly one release below the change
  #   because `create_concat_dataset` opens a dataset and its splits as separate
  #   handles.  The fix is to carry py-lmdb 1.7.3 and drop this entry, which is
  #   queued in ../../docs/TODO.md; it also recovers the two LMDB modules
  #   ../ase-db-backends deselects.
  #
  #   setuptools `<81.0.0` against 83.0.0.  This one is not about fairchem's own
  #   code, which never imports setuptools or pkg_resources: `core/__init__.py`
  #   installs a `filterwarnings` for a pkg_resources deprecation warning and
  #   says in a TODO that it is torchtnt's to fix.  So the cap keeps
  #   pkg_resources present for torchtnt, and that is torchtnt's problem to have
  #   rather than a reason to hold this package back.
  #
  # `monty >= 2026.2.18` needs no relaxing, though nixpkgs' monty is 2025.3.3 —
  # this overlay replaces it with the 2026.7.16 backport that ../pymatgen-core
  # needs.  See ../monty.
  pythonRelaxDeps = [
    "lmdb"
    "numpy"
    "setuptools"
    "torch"
  ];

  # `fairchem/core/_config.py` runs `os.makedirs(CACHE_DIR, exist_ok=True)` at
  # module scope, with CACHE_DIR defaulting under `~/.cache`, so merely
  # *importing* fairchem.core fails on stdenv's unwritable `/homeless-shelter`.
  # In `preBuild` rather than `preCheck` because `pythonImportsCheck` is what
  # trips it and that runs outside the check phase.  Third package here with
  # this exact shape, after ../matgl and ../maml.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # `ray[serve]`, and the extra is **not** optional the way it looks.  Importing
  # `fairchem.core` at all reaches it: `__init__.py` imports
  # `calculate.pretrained_mlip`, which pulls `calculate/_batch.py`, which pulls
  # `components/batch_server.py`, which opens `from ray import serve` at module
  # scope.  Without it the very first import dies on
  # `ModuleNotFoundError: No module named 'starlette'`.
  #
  # nixpkgs' ray carries the extra as `optional-dependencies.serve`, so this is
  # the literal translation of the requirement rather than a hand-picked list of
  # what starlette happens to need today.
  #
  # Four more that upstream declares under its `extras` group, or not at all,
  # and that are nonetheless imported at module scope in library code — so the
  # modules holding them cannot be imported without them:
  #
  #   pyarrow    components/calculate/simulation_tools/trajectory.py, reached
  #              straight from `components/calculate/__init__.py`
  #   pandas     components/common/load_dataframe.py and the whole of
  #              components/benchmark/
  #   pymatgen   components/calculate/recipes/utils.py
  #   matplotlib models/uma/escn_moe.py — library code, not one of the scripts
  #
  # This is ../vise's lesson for the second time in one package, after
  # `ray[serve]`: reading what a project *declares* is not reading what it
  # imports.  pyarrow was found by a test run rather than by the import check,
  # because that check named `fairchem.core.calculate` and the failure was in
  # `fairchem.core.components.calculate` — a different module one word apart.
  # `pythonImportsCheck` below now covers the components tree for that reason.
  dependencies = [
    ase
    ase-db-backends
    clusterscope
    e3nn
    huggingface-hub
    hydra-core
    lmdb
    matplotlib
    monty
    numba
    numpy
    orjson
    pandas
    pyarrow
    pymatgen
    pyyaml
    ray
    requests
    scipy
    setuptools
    submitit
    torch
    torchtnt
    tqdm
    wandb
    websockets
  ]
  ++ ray.optional-dependencies.serve;

  # Upstream's `test` requirements, less what is already a dependency above and
  # less `pytest-xdist`, which is deliberately absent — see ../doped and
  # ../fireworks for what parallel workers do to a suite that was not written
  # for them, and note that nothing here has been shown to need it.
  #
  # `syrupy` is the snapshot plugin several of the model tests assert through;
  # without it they fail at fixture resolution rather than skipping.  The rest
  # are ordinary imports scattered through `tests/core`.
  nativeCheckInputs = [
    pytestCheckHook
    filelock
    omegaconf
    scikit-learn
    syrupy
  ];

  # The suite lives in `tests/` at the *repository* root, two levels above the
  # `sourceRoot` the wheel is built from.  The whole repo is unpacked, so
  # reaching it is a `cd` rather than a second build — this was `doCheck =
  # false` for a while on the theory that `sourceRoot` put the tests out of
  # reach, and that was simply wrong.
  # One consequence worth knowing: upstream's `[tool.pytest.ini_options]` lives
  # in `packages/fairchem-core/pyproject.toml`, and pytest finds its rootdir by
  # walking *up* from the arguments.  From `tests/core` that walk reaches the
  # repository root, which carries no pytest config at all, so upstream's
  # `addopts` does not apply here.  That is a gain rather than a loss — the
  # first entry in it is `-x`, which would stop at the first failure and hide
  # every one behind it, and this repository would rather see the whole list.
  preCheck = ''
    cd ../..
  '';

  # `tests/core` only.  The sibling trees test the other twelve distributions of
  # the monorepo — `tests/data`, `tests/applications`, `tests/demo`,
  # `tests/lammps` — none of which are packaged, and `tests/perf` is a
  # benchmark.
  enabledTestPaths = [ "tests/core" ];

  # Ten of the eighty modules under `tests/core`, and every one of them for a
  # reason that is about the environment rather than about fairchem:
  #
  #   `test_omol_recipes.py` imports `components/calculate/recipes/omol.py`,
  #   the one library module here that reaches a sibling distribution at module
  #   scope — `from fairchem.data.omol.orca.calc import EVAL_OPT_PARAMETERS` —
  #   so it needs `fairchem-data-omol`, which is not packaged.  It is the test
  #   counterpart of the module already left out of `pythonImportsCheck` below,
  #   and it has to go too: a collection error aborts the entire run, so this
  #   one module was hiding the other seventy.
  #
  #
  #   Seven load a pretrained UMA checkpoint through
  #   `pretrained_mlip.get_predict_unit`, which fetches from Hugging Face.
  #   `tests/core/conftest.py` imports that module too, but only imports it —
  #   the fixtures that download are lazy, so the conftest itself is fine and
  #   the other seventy-one modules collect normally.
  #
  #   `test_torchsim_interface.py` needs torch-sim and `test_radius_graph.py`
  #   needs `nvalchemi-toolkit-ops`; both are behind the NVIDIA wall that keeps
  #   torch-sim, orb-models, mattersim and pet-mad unpackaged.  See "Deferred
  #   packaging" in ../../AGENTS.md.
  disabledTestPaths = [
    "tests/core/calculate/test_ase_calculator.py"
    "tests/core/calculate/test_pretrained_mlip.py"
    "tests/core/calculate/test_torchsim_interface.py"
    "tests/core/components/benchmark/test_perf_check.py"
    "tests/core/components/test_omol_recipes.py"
    "tests/core/graph/test_radius_graph.py"
    "tests/core/models/allscaip/test_allscaip_calculator.py"
    "tests/core/models/uma/uma_fast/test_execution_backends.py"
    "tests/core/units/mlip_unit/test_predict.py"
    "tests/core/units/mlip_unit/test_stress_predict.py"
  ];

  # `fairchem.core.components.calculate.recipes.omol` is deliberately absent: it
  # is the one module in this distribution that imports a sibling distribution
  # at module scope and unguarded, `from fairchem.data.omol.orca.calc import
  # EVAL_OPT_PARAMETERS`, so it cannot import without `fairchem-data-omol`.  The
  # other two cross-package imports — in `calculate/ase_calculator.py` and
  # `recipes/adsorbml.py` — sit inside `try:` blocks and degrade.  Same shape as
  # ../dbstep's `dbstep.graph` and ../dargs' `dargs.sphinx`.
  #
  # `calculate.ase_calculator` is named because it is what matcalc and quacc
  # actually reach for, and ../vise is the reminder of why that matters.
  pythonImportsCheck = [
    "fairchem.core"
    "fairchem.core.calculate"
    "fairchem.core.calculate.ase_calculator"
    "fairchem.core.components.benchmark"
    "fairchem.core.components.calculate"
    "fairchem.core.datasets"
    "fairchem.core.units"
  ];

  meta = {
    description = "Machine learning models for chemistry and materials science by the FAIR Chemistry team";
    homepage = "https://github.com/facebookresearch/fairchem";
    changelog = "https://github.com/facebookresearch/fairchem/releases/tag/fairchem_core-${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "fairchem";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
