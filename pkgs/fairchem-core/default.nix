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
  monty,
  numba,
  numpy,
  orjson,
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
  #   numpy `<2.5` against 2.5.1, and lmdb `<=1.7.3` against 2.3.0.  Defensive
  #   upper caps of the usual kind.
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

  # `ray[serve]` upstream; the extra pulls a FastAPI serving stack that only the
  # cluster launchers use, and nixpkgs' `ray` is the base distribution.
  dependencies = [
    ase
    ase-db-backends
    clusterscope
    e3nn
    huggingface-hub
    hydra-core
    lmdb
    monty
    numba
    numpy
    orjson
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
  ];

  # Not run, for two independent reasons.  The suite lives in `tests/` at the
  # *repository* root, which is outside the `sourceRoot` above — the wheel is
  # built from `packages/fairchem-core/`, so pytest would have nothing to
  # collect without building this a second way.  And the tests that matter load
  # UMA checkpoints through `pretrained_mlip.get_predict_unit`, which fetches
  # from Hugging Face; the same reason ../matgl, ../matcalc and ../mp-api do not
  # run theirs.
  doCheck = false;

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
