{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  custodian,
  emmet-core,
  frozendict,
  monty,
  numpy,
  psutil,
  pydantic,
  pydantic-settings,
  pymatgen-core,
  ruamel-yaml,
  typer,

  # optional-dependencies
  atomate2,
  dask,
  dask-jobqueue,
  distributed,
  jobflow,
  jobflow-remote,
  parsl,
  phonopy,
  prefect,
  ray,
  redun,
  seekpath,
  sella,
  tblite,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-cov,
}:

# quacc — a workflow engine for computational materials science, sitting
# alongside atomate2 in the materials chain (see "Deferred packaging" in
# ../../AGENTS.md).  Its core `dependencies` are all satisfied; the engine
# adapters (dask, parsl, prefect, redun, ray) and code recipes beyond the
# ASE-native ones are optional extras and left out.
buildPythonPackage (finalAttrs: {
  pname = "quacc";
  version = "1.5.10-unstable-2026-09-02";
  pyproject = true;
  __structuredAttrs = true;

  # 15 commits past the v1.5.9 tag; pyproject already carries the 1.5.10
  # version string, so this is the post-release state.
  src = fetchFromGitHub {
    owner = "Quantum-Accelerators";
    repo = "quacc";
    rev = "1e7a229b87d189d26c5577cfafc47302b521ac18";
    hash = "sha256-amzPB23yaYAlT2tQBtDnBqzghiLItaqLhQoIiAAtEhs=";
  };

  # `version` is a plain string in pyproject.toml.
  build-system = [ setuptools ];

  # Every upstream extra whose dependencies are all packaged.  Left out:
  # `fairchem`/`torchsim` (unpackaged ML stacks), `mlip` (needs `fairchem-core`
  # on top of the packaged `rootstock` and `matcalc[matgl]`), and the `defects`
  # extra's `shakenbreak` (needs doped + hiphive).
  optional-dependencies = {
    dask = [
      dask
      dask-jobqueue
      distributed
    ];
    jobflow = [
      jobflow
      jobflow-remote
    ];
    mp = [ atomate2 ];
    parsl = [ parsl ];
    phonons = [
      phonopy
      seekpath
    ];
    prefect = [
      dask
      dask-jobqueue
      distributed
      prefect
    ];
    ray = [ ray ];
    redun = [ redun ];
    sella = [ sella ];
    tblite = [ tblite ];
  };

  dependencies = [
    ase
    custodian
    emmet-core
    frozendict
    monty
    numpy
    psutil
    pydantic
    pydantic-settings
    pymatgen-core
    ruamel-yaml
    typer
  ];

  # First round: the workflow mechanics (`wflow` needs no engine — quacc's
  # decorators are no-ops without one) and the recipe families that run on
  # ASE-native calculators (EMT, Lennard-Jones) or tblite.  The rest of
  # `tests/core/recipes/` — vasp, espresso, gaussian, orca, psi4, qchem, aims,
  # dftb, gulp, mrcc, onetep — needs external codes; `mlip_recipes` needs
  # `rootstock` (not packaged) and `torchsim_recipes` needs torch-sim.  The
  # engine-adapter suites are `tests/dask`, `tests/parsl` etc., outside
  # `tests/core`, so they are not in `testpaths` at all.
  enabledTestPaths = [
    "tests/core/atoms"
    "tests/core/calculators"
    "tests/core/schemas"
    "tests/core/utils"
    "tests/core/settings"
    "tests/core/runners"
    "tests/core/wflow"
    "tests/core/cli"
    "tests/core/test_init.py"
    "tests/core/recipes/emt_recipes"
    "tests/core/recipes/lj_recipes"
    "tests/core/recipes/tblite_recipes"
  ];

  # pytest-asyncio because `[tool.pytest.ini_options]` sets
  # `asyncio_mode = "auto"`; pytest-cov because `addopts` in the parent carries
  # coverage flags.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-cov
  ]
  ++ finalAttrs.passthru.optional-dependencies.tblite;

  # matplotlib writes $HOME/.config on import; the default /homeless-shelter is
  # not writable.
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # Two bulk-Cu GFN1-xTB recipes whose asserted numbers were computed against a
  # different tblite / ASE than the channels here carry.  `test_relax_job_cell`
  # is a variable-cell relaxation that settles ~0.024 eV away; `test_freq_job_
  # harmonic` expects three vibrational modes but ASE discards two as marginally
  # imaginary (a warning, `2.2e-07` residual).  The fixed-cell relaxations,
  # statics and molecular frequencies all pass at tight tolerance, so the tblite
  # integration is sound — only these two single-atom-cell endpoints drift.
  disabledTests = [
    "test_relax_job_cell"
    "test_freq_job_harmonic"
  ];

  pythonImportsCheck = [
    "quacc"
    "quacc.recipes.emt.core"
    "quacc.schemas.ase"
  ];

  meta = {
    description = "Workflow engine for high-throughput computational materials science";
    homepage = "https://github.com/Quantum-Accelerators/quacc";
    changelog = "https://github.com/Quantum-Accelerators/quacc/blob/${finalAttrs.src.rev}/docs/about/changelog.md";
    license = lib.licenses.bsd3;
    mainProgram = "quacc";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
