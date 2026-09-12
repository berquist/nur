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
  pymatgen-io-aims,
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
  #
  # The second hunk makes one CP2K test's timestamp regex accept a whole
  # second, and it is nix's clock rather than atomate2's parser that forces it.
  # The drone reads `completed_at` off the output file's mtime, and
  # `test_structure_optimization` asserts that string's *format*:
  #
  #   assert re.match(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\+\d{2}:\d{2}$",
  #                   doc.completed_at)
  #
  # The unpack phase normalises every mtime in the source tree to
  # `SOURCE_DATE_EPOCH` — this build logs it as timestamp 315619200 — so the
  # drone reads back `1980-01-02 00:00:00+00:00`.  `str(datetime)` omits the
  # microseconds when they are zero, `\.\d{6}` never matches, and no
  # reproducible build can satisfy that pattern whatever the drone does.
  #
  # `(\.\d{6})?` rather than deleting the assertion, and rather than
  # deselecting the test as this first did.  The three things the assertion is
  # really for — that `completed_at` is populated, that it is a date and time
  # rather than a float or a `datetime`, and that it carries a UTC offset —
  # all survive; only the sub-second precision, which is the one part nix
  # guarantees will be absent, stops being required.  Upstream would see no
  # change: a real mtime has microseconds and still matches.
  #
  # It is also the reason this is a one-line substitution.  Rewriting the
  # regex literal alone touches no Python indentation, where deleting the
  # assertion meant embedding a four-space-indented block in an indented
  # string and relying on the strip to put it back.  The literal appears
  # exactly once in the repository.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${lib.head (lib.splitString "-" finalAttrs.version)}"

    [tool.versioningit.vcs]'

    substituteInPlace tests/cp2k/test_drones.py \
      --replace-fail \
        'r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\+\d{2}:\d{2}$"' \
        'r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d{6})?\+\d{2}:\d{2}$"'
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
  # `abinit` (abipy), `amset` — are not, and are omitted rather than partially
  # filled.
  #
  # `aims` names `pymatgen-io-aims` beside a `pymatgen` this already has.  The
  # first of those is the distribution pymatgen shed when it split in 2026, and
  # packaging it — with ../pyfhiaims beneath it — is what turns `tests/aims`
  # from a collection error into 22 tests.  See ../pymatgen-io-aims' header.
  optional-dependencies = {
    aims = [ pymatgen-io-aims ];
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
  # The six that follow it were held back on the strength of the programs their
  # names mention, which was the wrong question to ask: **every one of them
  # mocks the run**, in the same `fake_run_*` shape `tests/vasp` established.
  # `tests/aims`' conftest is the most explicit about it — a `mock_aims`
  # fixture, and a `--generate-test-data` option you pass to invoke the real
  # FHI-aims instead.  That is 120 tests that were being skipped by omission.
  #
  # Five of the six needed nothing at all: they import only what atomate2
  # already depends on, and never call `shutil.which`.  `tests/aims` needed one
  # package, and not the program — `pymatgen.io.aims`, which upstream moved
  # *out* of pymatgen when it split in 2026 and which is now the separate
  # `pymatgen-io-aims` distribution, declared in the `aims` extra above.
  # Without it, collecting `tests/aims/conftest.py` fails outright with
  # `ModuleNotFoundError: No module named 'pymatgen.io.aims'`.
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
    "tests/aims"
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

  # `atomate2/common/jobs/mpmorph.py` makes `~/.cache/atomate2` at *import*, at
  # module scope and unguarded, so the default `/homeless-shelter` turns into a
  # `PermissionError` — reported 32 times over, once per xdist worker, as a
  # collection error on `tests/common/jobs/test_mpmorph.py`.  ../matgl,
  # ../fairchem-core, ../maml and ../fairchem-data-oc all carry the same three
  # lines for the same reason.
  #
  # `preBuild` rather than `preCheck` because that is where the habit came
  # from: in those four it is `pythonImportsCheck` that trips, and that phase
  # runs outside the check phase.  It does not trip here — none of the four
  # modules named below reaches mpmorph — but keeping the hook the same across
  # all five is worth more than saving a phase.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # `-rsfE`, so that what this suite declines to run says so in the build log.
  # Two icet SQS cases, one unconditionally skipped cclib module, and one
  # `tests/common/test_jobs.py` case wanting a Materials Project API key are
  # the standing set, plus `test_packmol_job` wherever `packmol` above came
  # back null; anything else in that report is an input that did not arrive.
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
