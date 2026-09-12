{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  click,
  custodian,
  emmet-core,
  jobflow,
  monty,
  numpy,
  pydantic,
  pydantic-settings,
  pymatgen,
  pymatgen-core,
  pymongo,
  pyyaml,

  # optional-dependencies
  ase,
  dscribe,
  ijson,
  lobsterpy,
  mp-api,
  phonopy,
  pymatgen-analysis-defects,
  pymatgen-analysis-diffusion,
  python-ulid,
  seekpath,
  tblite,

  # tests
  pytestCheckHook,
  pytest-cov,
  pytest-mock,
  pytest-xdist,
  enumlib,
  fireworks,

  # packmol, for the one test in `tests/common/jobs/test_mpmorph.py` that gates
  # on `which("packmol")` — `MPMorphMDMaker` shells out to it to pack an
  # amorphous box.  Defaulted and resolved in ../../overlays/default.nix
  # exactly as ../fairchem-data-oc's is, for the same two reasons: nixpkgs has
  # no packmol at all, and `overlays/` is imported without flakes so it cannot
  # reach the `nixos-qchem` input that does.  See "Reusing NixOS-QChem" in
  # ../../AGENTS.md, and `checks.atomate2` in ../../flake.nix, which is the one
  # place this repository builds atomate2 with it.
  packmol ? null,
}:

# atomate2 — the library of Materials Project workflows, and the near-term
# target of the materials chain (see "Deferred packaging" in ../../AGENTS.md).
# Its full `dependencies` set is now satisfiable; the many optional extras that
# need packages no channel here carries (chgnet, mace, openff, torch-sim, abipy)
# are simply left out.
buildPythonPackage (finalAttrs: {
  pname = "atomate2";
  version = "0.1.5-unstable-2026-08-31";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v0.1.5 tag, 20 behind it — the interim commits are
  # mostly dependabot bumps but include a `VaspInputGenerator` field-shadowing
  # fix, a duplicate-input-set removal, and the `pymatgen-core` bump to
  # 2026.8.13, which is the version this repo carries.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "atomate2";
    rev = "14bacb526a022140318b3016adf3b6ea8bde1188";
    hash = "sha256-w2jFnZwqIQjg3lsTuN6WG70Xl8h6uZD5mEoiBHyXXCg=";
  };

  # versioningit's `method = "git"` against a fetchFromGitHub tarball with no
  # repository; the top-level `default-version` is the fallback it uses for any
  # error during version calculation, and upstream declares only the `vcs`
  # sub-table.  See ../qtoolkit for the full account.  The `-unstable-` suffix
  # is not PEP 440, so only the part before the first dash goes in.
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
    click
    custodian
    emmet-core
    jobflow
    monty
    numpy
    pydantic
    pydantic-settings
    pymatgen
    pymatgen-core
    pymongo
    pyyaml
  ];

  # The extras whose dependencies are all packaged here.  The rest —
  # `forcefields` (chgnet, mace, sevenn…), `openmm`/`openff`, `torchsim`,
  # `abinit` (abipy), `aims`, `amset` — are not, and are omitted rather than
  # partially filled.
  optional-dependencies = {
    ase = [ ase ];
    ase-ext = [ tblite ];
    mp = [ mp-api ];
    lobster = [
      ijson
      lobsterpy
    ];
    phonons = [
      phonopy
      seekpath
    ];
    defects = [
      dscribe
      pymatgen-analysis-defects
      python-ulid
    ];
    approxneb = [ pymatgen-analysis-diffusion ];
  };

  # `tests/vasp` is the core and mocks VASP execution against 340 MB of
  # reference data — and its flow tests reach into the phonon, defect,
  # approx-NEB, electrode and lobster workflows, so all the extras above are
  # check inputs.
  #
  # The five that follow it were held back on the strength of the programs
  # their names mention, which was the wrong question to ask: **every one of
  # them mocks the run**, in the same `fake_run_*` shape `tests/vasp`
  # established, and between them they import nothing outside atomate2's own
  # dependency set and never call `shutil.which`.  That is 98 tests that were
  # being skipped by omission.
  #
  # `tests/aims` is the sixth of that group and the one exception, though not
  # for the reason the old comment gave: its conftest is explicit that it mocks
  # FHI-aims too (a `mock_aims` fixture, and `--generate-test-data` to run the
  # real thing).  What it needs is Python — `pymatgen.io.aims`, which upstream
  # moved *out* of pymatgen when it split in 2026.  It is now a distribution of
  # its own, `pymatgen-io-aims`, alongside `pymatgen-io-fleur`; see the note at
  # the end of `pymatgen/io/registry.py` in `pymatgen-core`, which carries
  # compatibility shims for both.  atomate2 names it in an `aims` extra this
  # derivation does not declare, so collecting `tests/aims/conftest.py` fails
  # outright with `ModuleNotFoundError: No module named 'pymatgen.io.aims'`.
  # Packaging it is the whole of the work; see ../../docs/TODO.md.
  #
  # `tests/common` was written off here as needing cclib and icet, and needs
  # neither to be worth running: its one cclib module carries an unconditional
  # `@pytest.mark.skip(reason="cclib is not working in CI")` upstream, and icet
  # gates two SQS tests out of 37.  What it does have is
  # `test_mpmorph.py::test_packmol_job`, on `which("packmol")` — see the
  # `packmol` argument above.
  #
  # Still out, and genuinely so: `tests/forcefields` (torch, plus chgnet/mace
  # model weights), `tests/openff_md` and `tests/openmm_md` (the openff stack,
  # which is conda-first — see ../../AGENTS.md), `tests/torchsim` and
  # `tests/abinit` (torch-sim and abipy, neither packaged).
  enabledTestPaths = [
    "tests/vasp"
    "tests/ase"
    "tests/lobster"
    "tests/common"
    "tests/cp2k"
    "tests/jdftx"
    "tests/lammps"
    "tests/qchem"
  ];

  # pytest-cov because `[tool.pytest.ini_options] addopts` carries
  # `--cov-config=pyproject.toml`, which pytest rejects as an unknown argument
  # without the plugin.
  #
  # enumlib for `test_magnetic_orderings`, whose flow runs pymatgen's
  # `MagneticStructureEnumerator`.  It has to be on PATH rather than merely
  # installed: pymatgen's `enumlib_caller` resolves `enum.x` and `makestr.x`
  # into module-level constants at import time and refuses to construct an
  # `EnumlibAdaptor` if either is missing.  Not in nixpkgs; see ../enumlib.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
    pytest-mock
    pytest-xdist
    enumlib
    fireworks
  ]
  ++ lib.optional (packmol != null) packmol
  ++ lib.concatLists (builtins.attrValues finalAttrs.passthru.optional-dependencies);

  # `-rsfE`, so that what this suite declines to run says so in the build log.
  # Two icet SQS cases and one unconditionally skipped cclib module are the
  # standing set, plus `test_packmol_job` wherever `packmol` above came back
  # null; anything else in that report is an input that did not arrive.
  #
  # `f` and `E` are not decoration: pytest's `-r` *replaces* the default report
  # characters rather than adding to them, and the default is `fE`.  A bare
  # `-rs` therefore buys the skip list at the cost of the failure list, which
  # is how the first run of this change reported four failures and named none
  # of them.  ../parmed passes `-rsfE` for exactly this reason; ../fireworks'
  # `-rs` predates the discovery.
  pytestFlags = [ "-rsfE" ];

  pythonImportsCheck = [
    "atomate2"
    "atomate2.vasp.flows.core"
    "atomate2.vasp.jobs.core"
    "atomate2.ase.jobs"
  ];

  meta = {
    description = "Library of computational materials science workflows";
    homepage = "https://github.com/materialsproject/atomate2";
    changelog = "https://github.com/materialsproject/atomate2/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.bsd3Lbnl;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
