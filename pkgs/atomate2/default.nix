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
  fireworks,
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

  # First round: the workflow families whose code and test dependencies are all
  # present.  `tests/vasp` is the core and mocks VASP execution against 340 MB
  # of reference data — and its flow tests reach into the phonon, defect,
  # approx-NEB, electrode and lobster workflows, so all the extras above are
  # check inputs.  The rest — `tests/common` (cclib, icet),
  # `tests/forcefields`, `tests/openff_md`, `tests/torchsim`, `tests/abinit`,
  # `tests/aims`, `tests/cp2k`, `tests/qchem`, `tests/jdftx`, `tests/lammps` —
  # wait on packages no channel here carries.
  enabledTestPaths = [
    "tests/vasp"
    "tests/ase"
    "tests/lobster"
  ];

  # pytest-cov because `[tool.pytest.ini_options] addopts` carries
  # `--cov-config=pyproject.toml`, which pytest rejects as an unknown argument
  # without the plugin.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
    pytest-mock
    pytest-xdist
    fireworks
  ]
  ++ lib.concatLists (builtins.attrValues finalAttrs.passthru.optional-dependencies);

  disabledTests = [
    # `MagneticStructureEnumerator` shells out to enumlib's `enum.x` / `makestr.x`
    # Fortran executables, which are not in nixpkgs.
    "test_magnetic_orderings"
  ];

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
