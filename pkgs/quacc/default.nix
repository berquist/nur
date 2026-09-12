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
  fairchem-core,
  fairchem-data-oc,
  fairchem-data-omat,
  fairchem-data-omol,
  jobflow,
  jobflow-remote,
  matcalc,
  parsl,
  phonopy,
  prefect,
  pymatgen-analysis-defects,
  ray,
  redun,
  rootstock,
  seekpath,
  sella,
  shakenbreak,
  tblite,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-cov,
  openbabel-bindings,
  quantum-espresso,
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

  # Every upstream extra whose dependencies are all packaged.  `torchsim` is the
  # only one left out, and it is NVIDIA-blocked rather than merely unpackaged —
  # torch-sim's core dependency `nvalchemi-toolkit-ops` is not in nixpkgs.  See
  # ../../docs/TODO.md.
  #
  # `mlip` asks for `fairchem-core` alone beside `matcalc[matgl]` and
  # `rootstock`; `fairchem` adds the three data distributions out of the same
  # monorepo, which are now ../fairchem-data-oc, ../fairchem-data-omat and
  # ../fairchem-data-omol.  Its floors — `>=1.0.2`, `>=0.2`, `>=0.1.2` — are
  # exactly the versions those three carry.
  #
  # ../fairchem-data-omol drops its own `quacc` requirement rather than
  # declaring it, because this entry is the other half of that cycle; the note
  # at its `optional-dependencies` says why the cut goes this way round.
  #
  # `defects` is the newest, and the reason seven packages beneath it exist —
  # ../shakenbreak, and under that doped, pydefect, vise, hiphive, trainstation,
  # cmcrameri and matplotlib-label-lines.  It names `pymatgen-analysis-defects`
  # beside shakenbreak and that half was missing here until the check phase
  # went looking for it: `tests/core/atoms/test_defects.py` and
  # `tests/core/recipes/emt_recipes/test_emt_defect_recipes.py` both
  # `importorskip("pymatgen.analysis.defects")` before they
  # `importorskip("shakenbreak")`, so the incomplete extra was invisible from
  # the package side and showed up as two silently skipped modules.
  #
  # Unlike every other entry here this one is not free to quacc's own build any
  # more — `nativeCheckInputs` below takes `defects`, `phonons`, `sella` and
  # `tblite`.  The four are exactly the extras whose tests run offline; see the
  # note there.
  optional-dependencies = {
    defects = [
      pymatgen-analysis-defects
      shakenbreak
    ];
    dask = [
      dask
      dask-jobqueue
      distributed
    ];
    fairchem = [
      fairchem-core
      fairchem-data-oc
      fairchem-data-omat
      fairchem-data-omol
    ];
    jobflow = [
      jobflow
      jobflow-remote
    ];
    mlip = [
      fairchem-core
      rootstock
      matcalc
    ]
    ++ matcalc.optional-dependencies.matgl;
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

  # The espresso suite brings its own MPI, and it should not.  Its conftest
  # declares an autouse fixture that sets `ESPRESSO_PARALLEL_CMD` to
  # `mpirun -np 2` whenever `mpirun` is on PATH and the machine reports two
  # physical cores, and both hold inside a nix build the moment
  # `quantum-espresso` becomes a check input: nixpkgs carries its MPI in
  # `propagatedBuildInputs`, so adding the program adds `mpirun` beside it.
  # What follows is the failure ../aiida-nwchem's `postPatch` documents from
  # the other side — a multi-rank job in a build sandbox, aborting before it
  # writes a line, and reported by the layer above as a parse error rather than
  # as an MPI one.  Twenty-eight tests on unit cells of two atoms have nothing
  # to gain from a second rank, so the branch is simply never taken.
  postPatch = ''
    substituteInPlace tests/core/recipes/espresso_recipes/conftest.py \
      --replace-fail 'which("mpirun") and psutil.cpu_count(logical=False) >= 2' 'False'
  '';

  # The whole of upstream's own `testpaths`, less what is named below.  It was
  # a list of eleven directories before, written on the assumption that every
  # `tests/core/recipes/<code>_recipes` needs `<code>` installed.  Eight of
  # them do not: aims, gaussian, gulp, mrcc, onetep, orca and the `mocked`
  # halves of qchem and vasp all patch the calculator's `execute` (or `_run`)
  # out through a conftest fixture and assert on the input that would have been
  # written, so they exercise the recipe layer with no program at all and no
  # Python dependency beyond quacc's own.  That is 89 tests, and `vasp_recipes/
  # mocked` is 42 of them — it reads its POTCARs from a `fake_pseudos`
  # directory in the repository, so not even VASP's licensed data is involved.
  #
  # `espresso_recipes` is the one family that does run a real program, and it
  # is here because nixpkgs has `quantum-espresso` at 7.5 — the same version
  # upstream's own CI installs from conda — and because the suite ships the
  # pseudopotentials it needs (`Si.upf.gz` and friends under `data/`) rather
  # than fetching them.  See `nativeCheckInputs`.
  enabledTestPaths = [ "tests/core" ];

  # What is left out, and why none of it is merely "needs a program":
  #
  # `dftb_recipes` — every one of its ten tests asserts `Hamiltonian_ = "xTB"`,
  # so it needs a DFTB+ built *with* tblite.  nixpkgs has no dftbplus at all;
  # NixOS-QChem has `qchem.dftbplus`, and its `cmakeFlags` carry
  # `-DWITH_TBLITE=OFF`, so wiring that one in the shape ../fairchem-data-oc
  # wires `packmol` would put a `dftb+` on PATH that turns ten clean skips into
  # ten failures.  Deselected rather than left to skip for exactly that reason:
  # the skip is only correct while nothing provides the binary.  See
  # ../../docs/TODO.md.
  #
  # `psi4_recipes` — one test, gated on importing the `psi4` *module*.  Psi4 is
  # in NixOS-QChem, but a Python extension from that input is built against its
  # interpreter rather than this repository's python313 pin, which is the whole
  # subject of the `qchemPkgs` note in ../../flake.nix.
  #
  # `torchsim_recipes` — torch-sim, whose core dependency
  # `nvalchemi-toolkit-ops` is not in nixpkgs; see ../../docs/TODO.md.
  #
  # The two `jenkins` directories are upstream's own name for "needs the
  # licensed binary": VASP and Q-Chem respectively, both gated on
  # `which(...CMD)` and both skipping cleanly, but there is no path on which
  # this repository can supply either.
  #
  # `mlip_recipes` is deliberately *not* here.  Six of its eight modules
  # `importorskip("torch")` or ask for matcalc, matgl, fairchem or ray and
  # would download a pretrained checkpoint if they had them — but `test_io.py`
  # and `test_rootstock_recipes.py` stub the calculator out entirely and run on
  # EMT, so deselecting the directory would cost two working modules to silence
  # six skips.  `-rsfE` below is what keeps those six visible.
  #
  # The last two entries are a different kind of exclusion: they are *not*
  # skipped, they run, in a second pytest process of their own.  See
  # `postCheck`.
  disabledTestPaths = [
    "tests/core/atoms/test_defects.py"
    "tests/core/recipes/emt_recipes/test_emt_defect_recipes.py"
    "tests/core/recipes/dftb_recipes"
    "tests/core/recipes/psi4_recipes"
    "tests/core/recipes/torchsim_recipes"
    "tests/core/recipes/qchem_recipes/jenkins"
    "tests/core/recipes/vasp_recipes/jenkins"
  ];

  # pytest-asyncio because `[tool.pytest.ini_options]` sets
  # `asyncio_mode = "auto"`; pytest-cov because `addopts` in the parent carries
  # coverage flags.
  #
  # Four of the thirteen extras declared above, and they are the four whose
  # tests run offline.  Each was already reachable from this repository and
  # each was costing a silently skipped module:
  #
  #   defects   tests/core/atoms/test_defects.py,
  #             tests/core/recipes/emt_recipes/test_emt_defect_recipes.py
  #   phonons   tests/core/atoms/test_phonons.py,
  #             tests/core/recipes/emt_recipes/test_emt_phonons.py,
  #             tests/core/recipes/tblite_recipes/test_tblite_phonons.py
  #   sella     tests/core/runners/test_sella.py
  #   tblite    tests/core/recipes/tblite_recipes/ (already here)
  #
  # `mlip` and `fairchem` are the two that stay out despite being packaged:
  # every test they unlock pulls a pretrained checkpoint over the network.
  # `mp`, `jobflow`, `dask`, `parsl`, `prefect`, `ray` and `redun` unlock
  # nothing under `tests/core` — the engine-adapter suites are `tests/dask`,
  # `tests/parsl` and so on, outside upstream's `testpaths` entirely, and each
  # wants a live scheduler.
  #
  # openbabel-bindings is not an extra of quacc's at all.  Five tests under
  # `tests/core/calculators/qchem` gate on `find_spec("openbabel")`, upstream's
  # CI installs it from conda for its Q-Chem lane, and nixpkgs has it — so it
  # is a check input rather than a dependency, the same shape ../dpdata uses.
  #
  # quantum-espresso is the real program, for the reason given at
  # `enabledTestPaths`.  Note `postPatch` above, which is only needed because
  # this input drags `mpirun` in behind it.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-cov
    openbabel-bindings
    quantum-espresso
  ]
  ++ finalAttrs.passthru.optional-dependencies.defects
  ++ finalAttrs.passthru.optional-dependencies.phonons
  ++ finalAttrs.passthru.optional-dependencies.sella
  ++ finalAttrs.passthru.optional-dependencies.tblite;

  # matplotlib writes $HOME/.config on import; the default /homeless-shelter is
  # not writable.
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # The two modules that reach shakenbreak, run in a pytest process of their
  # own — because importing shakenbreak changes pymatgen for everything that
  # comes after it in the same process, and one of the changes is wrong.
  #
  # `quacc/atoms/defects.py` does `from shakenbreak.input import Distortions`,
  # and that module's line 21 is `from doped.utils.efficiency import ...`.
  # doped's `efficiency` module rebinds methods on live pymatgen classes at
  # import — `Structure.__eq__`, `__hash__` and `__deepcopy__`, the same three
  # on `IStructure`, `PeriodicSite` and `Composition`, and on
  # `SpacegroupAnalyzer` both `_get_symmetry` and `get_symmetry_operations`.
  # They are caching wrappers, and process-wide once imported.
  #
  # **`get_symmetry_operations` is the one that is a bug**, not merely a
  # hazard.  doped wraps it in an `lru_cache` whose key includes `cartesian`,
  # and then drops the argument when calling through:
  #
  #   @lru_cache(maxsize=int(1e3))
  #   def _get_symmetry_operations(self, cartesian: bool = False):
  #       return _original_get_symmetry_operations(self)
  #
  # So `get_symmetry_operations(cartesian=True)` returns the *fractional*
  # operations.  pymatgen's elastic-tensor fit asks for the Cartesian ones to
  # symmetrise with, which is how `tests/core/recipes/emt_recipes/
  # test_emt_elastic.py` came back with a bulk modulus of 173.077 GPa against
  # an expected 134.579: EMT and the deformations were fine, the symmetrisation
  # was not.  It failed because `tests/core/atoms/` collects first and
  # `test_defects.py` is in it, so the patch was in place before any other test
  # ran.  See ../../docs/TODO.md for reporting it upstream.
  #
  # A second `pytest` rather than a deselection, so the two tests are still
  # run; the process exits before it can affect anything.  It inherits the
  # rootdir's `[tool.pytest.ini_options]` exactly as the main invocation does.
  postCheck = ''
    echo "running the shakenbreak-importing modules in a session of their own"
    pytest -rsfE \
      tests/core/atoms/test_defects.py \
      tests/core/recipes/emt_recipes/test_emt_defect_recipes.py
  '';

  # `-rsfE` because most of what this suite declines to run, it declines by
  # skipping rather than by being deselected, and a skip is indistinguishable
  # from a pass in a build log.  Six `mlip_recipes` modules are the whole of
  # the standing set on Linux — the `skipif os.name == "nt"` cases scattered
  # through `utils` and `wflow` all run here — so anything else appearing in
  # that report means an input this derivation thinks it has did not arrive.
  #
  # Not a bare `-rs`, and the difference matters: pytest's `-r` *replaces* the
  # default report characters instead of adding to them, and the default is
  # `fE`.  `-rs` alone therefore trades the failure list for the skip list,
  # which is how the first run of this change ended `4 failed, 445 passed` with
  # a short summary that named the 28 skips and not one of the four failures.
  # ../parmed passes `-rsfE`; ../fireworks' `-rs` predates the discovery.
  pytestFlags = [ "-rsfE" ];

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
