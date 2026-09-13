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
  pytest-xdist,
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
# `fairchem-data-{omat,oc,omol}` out of the same tree, and those are now
# ../fairchem-data-omat, ../fairchem-data-oc and ../fairchem-data-omol — so
# both that extra and `quacc[mlip]`, which asks for this distribution alone
# beside ../matcalc and ../rootstock, are reachable.
#
# The dependency runs one way only.  ../fairchem-data-oc needs this package;
# this package needs none of the three, and deliberately does not take
# fairchem-data-omol even though one of its modules imports it — see
# `pythonImportsCheck` below.
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
  #   `lmdb <= 1.7.3` is **not** relaxed, and was the one bound here that meant
  #   what it said.  Relaxing it cost about 43 of this suite's failures, all of
  #   them `create_concat_dataset` opening a dataset and its splits as separate
  #   handles against a py-lmdb that refuses the second open.  The overlay pins
  #   py-lmdb to 1.7.3 instead; see the `lmdb` binding in ../../overlays.
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

  # Upstream's `test` requirements, less what is already a dependency above.
  #
  # `pytest-xdist` is here, which is the exception to the rule ../doped and
  # ../fireworks set.  Those suites were never written for parallel workers;
  # this one is.  Upstream's CI runs `pytest -n auto` over everything except
  # three markers and a separate serial pass for one of them — see `pytestFlags`
  # and `postCheck` below, which reproduce that split.  A serial run of
  # `tests/core` takes 1221 s, and the machine it was measured on peaked at
  # 9.64 GB of 125 GB, so the memory headroom for workers is ample.
  #
  # `syrupy` is the snapshot plugin several of the model tests assert through;
  # without it they fail at fixture resolution rather than skipping.  The rest
  # are ordinary imports scattered through `tests/core`.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    filelock
    omegaconf
    scikit-learn
    syrupy
  ];

  # Upstream's own marker split, and `not serial` is the load-bearing half.
  #
  # `serial` marks tests that cannot share a session with parallel workers,
  # `test_graph_parallel.py` chief among them — it spawns torch multiprocessing
  # groups that would contend for ports.  Upstream excludes them from its
  # `-n auto` pass and runs them in a second serial one; `postCheck` below does
  # the same.  Without xdist this would be unnecessary; with it, it is what keeps
  # the suite honest.
  #
  # It is twelve `pytest.mark.serial` sites across seven modules, but only four
  # of them are on a function: `test_gp_utils.py`, `test_graph_parallel.py` and
  # `test_batcher.py` set a module-level `pytestmark`, so the count collected is
  # 100 rather than 12.  Three of the seven modules drop out again before the
  # serial pass runs anything — `test_graph_parallel.py` and `test_predict.py`
  # are in `disabledTestPaths` below, and `test_batcher.py` carries `gpu` in its
  # `pytestmark` list as well.
  #
  # `not gpu` is deliberate but *not* load-bearing, and worth being clear about:
  # `tests/conftest.py` already skips gpu-marked tests itself when
  # `torch.cuda.is_available()` is false, so this changes no outcome — it only
  # deselects 106 tests across 25 modules instead of collecting and setting each
  # of them up in order to skip it.  Time, not correctness.
  #
  # The markers are registered in `tests/conftest.py` through `addinivalue_line`,
  # so they resolve without any ini file — which matters, since running from the
  # repository root means upstream's `[tool.pytest.ini_options]` is not in scope.
  disabledTestMarks = [
    "gpu"
    "serial"
  ];

  # **The worker count is capped, and it has to be taken away from the hook to do
  # it.**  `pytest-xdist`'s own setup hook is
  #
  #     pytestXdistHook() { appendToVar pytestFlags "--numprocesses=$NIX_BUILD_CORES"; }
  #
  # registered in `preInstallCheckHooks` — so it appends to the *same* variable
  # this derivation sets, and appends later.  A `pytestFlags = [ "-n" "8" ]` here
  # would be overridden by the `--numprocesses=32` that follows it, silently,
  # because argparse takes the last occurrence.  `dontUsePytestXdist` is the
  # documented off switch for that hook; the count is then set in `preCheck`,
  # which `pytestCheckPhase` runs before it assembles `flagsArray`.
  #
  # Why cap it at all: on the machine this was measured on `NIX_BUILD_CORES` is
  # 32, and 32 workers drove peak memory to 119 GB of 125 GB with one worker
  # OOM-killed outright — `[gw23] node down: Not properly terminated`, which
  # failed a test for no reason of its own.  A serial run peaks at 9.6 GB, so the
  # marginal cost is about 6 GB per worker: eight of them measured 59 GB peak,
  # and 870 s against 3221 s serial and 441 s at thirty-two.  Upstream's
  # `-n auto` is safe for them only because their CI runners have two or four
  # cores.
  #
  # `min` rather than a flat 8, so a two-core builder still gets two workers
  # rather than eight fighting over it.
  dontUsePytestXdist = true;

  # The second pass, serial, exactly as upstream's workflow spells it.  Kept out
  # of `pytestFlags` because it is a separate pytest invocation rather than more
  # arguments to the first one — and *being* separate is the trap: pytestCheckHook
  # turns `disabledTestPaths` and `disabledTests` into flags for the phase's own
  # pytest call and for nothing else, so a bare `pytest` here inherits none of
  # them.  It has to repeat them, which is what the two `concatMapStringsSep`
  # lines do.  Without the `--ignore`s this pass dies exactly where the check
  # phase used to, on `test_omol_recipes.py` failing to import
  # `fairchem.data.omol` — and a collection error aborts the whole run, so the
  # four modules that do have serial tests never get to run at all.
  #
  # It is generated from the lists rather than written out so the two passes
  # cannot drift: adding a module to `disabledTestPaths` excludes it from both.
  postCheck = ''
    echo "running the serial-marked tests, without xdist"
    pytest tests/core -p no:cacheprovider -m 'serial and not gpu' \
      ${lib.concatMapStringsSep " " (p: "--ignore=${p}") finalAttrs.disabledTestPaths} \
      -k '${lib.concatMapStringsSep " and " (t: "not ${t}") finalAttrs.disabledTests}'
  '';

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

    # The unpack phase makes only `sourceRoot` writable, and `sourceRoot` here
    # is two directories down — so the tree we have just moved into is
    # read-only.  Anything the suite writes relative to the working directory
    # then fails: `test_relaxation_runner` calls `save_state("dummy_checkpoint")`,
    # which swallows the `EACCES` and returns False, surfacing as a bare
    # `assert False is True` with the cause only in a logged traceback.  pytest's
    # own cache warnings are the same problem, and are the easier tell.
    chmod -R u+w .

    # min(8, NIX_BUILD_CORES); see dontUsePytestXdist above for why this is not
    # simply an entry in pytestFlags.  NIX_BUILD_CORES can be 0, meaning "all",
    # in which case the cap is the whole answer.
    workers=8
    if [ "''${NIX_BUILD_CORES:-0}" -gt 0 ] && [ "$NIX_BUILD_CORES" -lt 8 ]; then
      workers="$NIX_BUILD_CORES"
    fi
    echo "pytest-xdist: $workers workers (NIX_BUILD_CORES=''${NIX_BUILD_CORES:-unset})"
    appendToVar pytestFlags "--numprocesses=$workers"
  '';

  # `tests/core` only.  The sibling trees test the other twelve distributions of
  # the monorepo — `tests/data`, `tests/applications`, `tests/demo`,
  # `tests/lammps` — none of which are packaged, and `tests/perf` is a
  # benchmark.
  enabledTestPaths = [ "tests/core" ];

  # Fourteen of the eighty modules under `tests/core`, and every one of them for a
  # reason that is about the environment rather than about fairchem:
  #
  #   `test_omol_recipes.py` imports `components/calculate/recipes/omol.py`,
  #   the one library module here that reaches a sibling distribution at module
  #   scope — `from fairchem.data.omol.orca.calc import EVAL_OPT_PARAMETERS`.
  #   That is what first put it on this list, and packaging
  #   ../fairchem-data-omol has since answered it; the module stays anyway,
  #   because it turns out to belong to the group below.  Every test in it is
  #   covered by a module-level `pytestmark = [pytest.mark.pretrained(...)]`
  #   and an autouse `pretrained_checkpoint` fixture, so all thirteen download
  #   a UMA checkpoint from Hugging Face before `setUp` finishes.  The import is
  #   the cheaper of its two blockers, not the real one.
  #
  #   Eight more load a pretrained UMA checkpoint through
  #   `pretrained_mlip.get_predict_unit`, which fetches from Hugging Face.
  #   `tests/core/conftest.py` imports that module too, but only imports it —
  #   the fixtures that download are lazy, so the conftest itself is fine and
  #   the other seventy-one modules collect normally.
  #
  #   `test_torchsim_interface.py` needs torch-sim, and four modules need
  #   `nvalchemi-toolkit-ops`: `test_radius_graph.py` and
  #   `test_graph_generation_nopbc.py` raise `RuntimeError: Requires
  #   ``nvalchemiops`` to be installed` directly, while
  #   `test_a2a_correctness.py` and `test_graph_parallel.py` raise it *inside*
  #   `torch.multiprocessing.spawn`, so they surface as a
  #   `ProcessRaisedException` and read at first glance like a distributed-setup
  #   problem.  They are not; the cause is the same missing package.  All of it
  #   is behind the NVIDIA wall that keeps torch-sim, orb-models, mattersim and
  #   pet-mad unpackaged — see "Deferred packaging" in ../../AGENTS.md and the
  #   nvalchemi entry in ../../docs/TODO.md.
  disabledTestPaths = [
    "tests/core/calculate/test_ase_calculator.py"
    "tests/core/calculate/test_pretrained_mlip.py"
    "tests/core/calculate/test_torchsim_interface.py"
    "tests/core/common/parallelism/test_a2a_correctness.py"
    "tests/core/common/parallelism/test_graph_parallel.py"
    "tests/core/components/benchmark/test_perf_check.py"
    "tests/core/components/test_omol_recipes.py"
    "tests/core/components/test_uma_speed_benchmark.py"
    "tests/core/graph/test_graph_generation_nopbc.py"
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
  # ../fairchem-data-omol is packaged now, so adding it here would make that
  # module import — and it stays out regardless.  Upstream's `pyproject.toml`
  # names it in no group at all, not even `extras`, so the honest reading is an
  # optional recipe that upstream forgot to guard rather than a dependency;
  # taking it would make every consumer of fairchem-core carry a package that
  # only the OMol ORCA recipes reach.  `quacc[fairchem]`, which is what actually
  # wants the pair, asks for both by name.
  #
  # `calculate.ase_calculator` is named because it is what matcalc and quacc
  # actually reach for, and ../vise is the reminder of why that matters.
  # One test, by name rather than by path — the module's other five pass.
  # `test_unified_matches_per_layer` is unique enough for `-k` to match it alone;
  # nothing else in the suite has it as a prefix.
  #
  # It asserts that `UnifiedRadialMLP` reproduces a list of eight `RadialMLP`s to
  # `atol = rtol = 1e-6`, and the two are the same arithmetic in a different
  # order: the unified form `torch.stack`s the eight layers' weights into batched
  # buffers and does one batched matmul where the reference does eight separate
  # ones.  Different BLAS kernel, different reduction order, different last bits.
  #
  # What makes 1e-6 unreachable rather than merely tight is the fixture: it
  # overwrites *every* parameter with `torch.randn_like`, LayerNorm scales
  # included, where those are normally 1.  Pushed through 64 -> 128 -> 128 -> 256,
  # the intermediates are far larger than in a trained model, and float32 spacing
  # at that magnitude is already around 1e-5.  The tolerance is below what the
  # type can represent there, so this is upstream's test to fix rather than a
  # property of this build — recorded in ../../docs/TODO.md.
  disabledTests = [ "test_unified_matches_per_layer" ];

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
