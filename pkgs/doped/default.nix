{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  cmcrameri,
  dscribe,
  filelock,
  matplotlib,
  matplotlib-label-lines,
  monty,
  numpy,
  pandas,
  pydefect,
  pymatgen,
  pymatgen-analysis-defects,
  scipy,
  spglib,
  sympy,
  tabulate,
  tqdm,
  vise,

  # tests
  pytestCheckHook,
  pytest-mpl,
}:

# doped — setup, processing and analysis of solid-state defect calculations with
# VASP.  The last package under `shakenbreak`, and so under `quacc[defects]`;
# see "Deferred packaging" in ../../AGENTS.md.  Internal, not re-exported.
buildPythonPackage {
  pname = "doped";
  version = "3.2.1-unstable-2026-05-18";
  pyproject = true;
  __structuredAttrs = true;

  # Three commits past the 3.2.1 tag, all of them documentation.
  src = fetchFromGitHub {
    owner = "SMTG-Bham";
    repo = "doped";
    rev = "9f08c3e18e7326b4973402e41bdc97cfdd11b31e";
    hash = "sha256-yQ3z/JJCdYErzSna68UFxvWPloHu0yzVs0BeQMpMi/Q=";
  };

  build-system = [ setuptools ];

  # doped and shakenbreak require each other, and this is where that cycle is
  # cut.  It is not a temporary measure for bootstrapping: nix cannot express
  # the cycle at all, so the requirement stays dropped for good.
  #
  # It has to be cut on this side.  shakenbreak imports doped at *module* scope,
  # in five of its modules — `cli`, `plotting`, `analysis`, `input`,
  # `energy_lowering_distortions` — so a shakenbreak without doped does not
  # import.  doped's own eight `import shakenbreak` statements are all inside
  # functions, so a doped without shakenbreak does.  shakenbreak is therefore
  # the half that declares the other, and `python3.withPackages` asking for
  # shakenbreak gets both.
  #
  # Something *is* lost, though, and it is worth being exact about what.  Two of
  # the three call sites degrade cleanly: `vasp.py`'s rattle option answers with
  # "ShakeNBreak must be installed (pip install shakenbreak) to use the rattle
  # option!", and the five `_install_custom_font` calls sit inside
  # `contextlib.suppress(Exception)`, so plots simply use the default font.  The
  # third does not: `utils/parsing.py` imports `get_homoionic_bonds` and
  # `get_dimer_bond_length` unguarded, so **dimer detection during defect
  # parsing raises without shakenbreak installed**.  That is what the twenty-one
  # deselections below are, and installing shakenbreak restores it.
  pythonRemoveDeps = [ "shakenbreak" ];

  # Upstream declares thirteen once shakenbreak is out.  monty, scipy, spglib,
  # sympy and tqdm are imported at module scope by `doped/` and declared by
  # nobody, so they are added — the same treatment as ../vise and ../pydefect.
  #
  # `pymatgen` rather than `pymatgen-core`, following upstream: doped reaches
  # the phase-diagram code that the 2026 split left in the outer half, and that
  # half depends on the core one.
  dependencies = [
    ase
    cmcrameri
    dscribe
    filelock
    matplotlib
    matplotlib-label-lines
    monty
    numpy
    pandas
    pydefect
    pymatgen
    pymatgen-analysis-defects
    scipy
    spglib
    sympy
    tabulate
    tqdm
    vise
  ];

  # pytest-mpl registers the `mpl_image_compare` marker that 121 tests across
  # eight modules carry.  `--mpl` is deliberately not passed, so the plotting
  # runs and the pixels go uncompared; see ../matplotlib-label-lines for the
  # same decision and why.
  #
  # **No pytest-xdist**, and this suite must never gain it — the same rule
  # ../fireworks carries, for a different reason.  Several of doped's
  # `setUpClass` methods stage their fixtures by *moving* directories inside the
  # source tree, `shutil.move`-ing e.g. `examples/CdTe/v_Cd_example_data/*` up
  # into `examples/CdTe/` and putting them back in `tearDownClass`.  Under
  # parallel workers that races itself: whichever worker runs second finds the
  # directory already gone, and the failure surfaces forty-odd files away as
  # `FileNotFoundError: .../examples/CdTe/...` or a bare `shutil.Error`, with
  # nothing pointing at the cause.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mpl
  ];

  # 414 MB of recorded VASP output under `tests/data`, which is most of why the
  # source is as large as it is.  None of it is installed: `packages.find`
  # excludes `tests*`.
  #
  # The suite does not need VASP itself.  Its POTCAR-dependent assertions are
  # behind `_potcars_available()`, whose docstring says as much — "If not
  # (testing on GitHub Actions), POTCAR testing will be skipped" — so upstream's
  # own CI runs it exactly the way this does.  That is the opposite of ../vise,
  # where the equivalent tests have no such guard.
  enabledTestPaths = [ "tests" ];

  # Four modules go wholesale, none of them for anything doped does wrong.
  disabledTestPaths = [
    # 69 tests, every one of them `ImportError: py-sc-fermi is not installed`.
    # Upstream's `tests` extra calls py-sc-fermi "not required, but allows
    # `FermiSolver` with `py-sc-fermi` backend to be tested" — which is to say
    # this module tests nothing else.  It is not in nixpkgs.
    "tests/test_fermisolver.py"

    # These three want a Materials Project account: 115 tests between them fail
    # with "The supplied API key (either ``api_key`` or 'PMG_MAPI_KEY' ...)".
    # They pull chemical potentials from the MP API, so they need a key and the
    # network, and a build sandbox has neither.
    "tests/test_chemical_potentials.py"
    "tests/test_plotting.py"
    "tests/test_thermodynamics.py"
  ];

  # `test_DefectsParser_CdTe` is deselected by node id rather than by name.
  # `disabledTests` matches on substrings, and this name is a prefix of eight
  # others — seven of them below, but `..._unrecognised_subfolder` passes and
  # would be taken with it.  Node ids are exact.  Same reason the `pymatgen`
  # binding in ../../overlays/default.nix deselects by node id.
  pytestFlags = [
    "--deselect=tests/test_analysis.py::DefectsParsingTestCase::test_DefectsParser_CdTe"
  ];

  # Every name below was read off a build log, and each is either the cycle cut
  # showing through or a dependency that has moved since upstream last recorded
  # its references.  None is a defect in doped or in this packaging.
  #
  # Matching is by substring, and the list has been checked against all 370
  # tests in the suite: no entry drops a test that is not itself here.  Two
  # entries are subsumed by another — `test_extrinsic_Sb2Se3` covers the
  # `_parsing_with_single_defect_dir` after it, and `test_agcu` covers
  # `test_agcu_no_generate_supercell` — and both are spelled out anyway, so the
  # list can be diffed against a log.
  disabledTests = [
    # --- shakenbreak: dimer detection in `utils/parsing.py`, imported
    # unguarded, so each of these raises `ModuleNotFoundError: No module named
    # 'shakenbreak'`.  See the note above `pythonRemoveDeps`.
    "test_BiOI_v_Bi_symmetry_determination"
    "test_CaO_symmetry_determination"
    "test_DefectsParser_CdTe_aniso_dielectric"
    "test_DefectsParser_CdTe_custom_settings"
    "test_DefectsParser_CdTe_filterwarnings"
    "test_DefectsParser_CdTe_kpoints_mismatch"
    "test_DefectsParser_CdTe_no_dielectric_json"
    "test_DefectsParser_CdTe_skip_corrections"
    "test_DefectsParser_CdTe_without_multiprocessing"
    "test_DefectsParser_YTOS_default_bulk"
    "test_DefectsParser_YTOS_explicit_bulk"
    "test_DefectsParser_YTOS_macOS_duplicated_OUTCAR"
    "test_DefectsParser_YTOS_macOS_duplicated_bulk_OUTCAR"
    "test_DefectsParser_corrections_errors_warning"
    "test_P1_sanity_check"
    "test_SrTiO3_diff_ISYM_bulk_defect_and_concentration_funcs"
    "test_V2O5_FNV"
    "test_V2O5_same_named_defects"
    "test_ZnS_non_diagonal_NKRED_mismatch"
    "test_bulk_symprec_and_periodicity_breaking_checks"
    "test_defect_from_structures_rattled"
    "test_duplicate_folders_Sb2Se3"
    "test_eigenvalues_parsing_and_warnings"
    "test_extrinsic_Sb2Se3"
    "test_extrinsic_Sb2Se3_parsing_with_single_defect_dir"
    "test_magnetization_parsing"
    "test_point_symmetry_periodicity_breaking"
    "test_poscar_comments"
    "test_rattled_CdTe_files"
    "test_sb2si2te6_eFNV"
    "test_shallow_defect_correction_warning_skipping"
    "test_solid_solution_oxi_state_handling"

    # --- no POTCARs.  Three assertions in `_write_and_check_dds_files` require
    # comment strings that doped writes into an INCAR only when it could read a
    # POTCAR — "needed if using the kumagai-oba" and the rest.  The
    # `_potcars_available()` guard that covers the rest of this module does not
    # reach inside that helper.
    "test_file_writing_with_without_POTCARs"
    "test_initialisation_for_all_structs"
    "test_neutral_defect_dict_set"

    # --- pymatgen moved.  This one asserts
    # `"1  # only one k-point" in dds.incar["KPAR"]`, which needs KPAR to be a
    # string carrying a trailing comment; pymatgen now parses it to an int, so
    # the assertion raises `TypeError: argument of type 'int' is not iterable`.
    # Upstream saw it coming — the line's own comment reads "pmg makes it
    # lowercase and can change".
    "test_bad_incar_setting"

    # --- the supercell search moved.  These compare against recorded supercell
    # matrices and defect tables.  `test_agcu` is the legible one: its
    # `min_image_distance` assertion passes and only the matrix differs, so
    # doped is finding an equally good supercell on a different lattice basis
    # than the reference was recorded with.  A different answer, not a wrong
    # one.
    "test_adsorbate_interstitial_generation_in_low_dimensional_structures"
    "test_agcu"
    "test_agcu_no_generate_supercell"
  ];

  pythonImportsCheck = [
    "doped"
    "doped.analysis"
    "doped.chemical_potentials"
    "doped.corrections"
    "doped.generation"
    "doped.thermodynamics"
    "doped.vasp"
  ];

  meta = {
    description = "Setup, processing and analysis of solid-state defect calculations with VASP";
    homepage = "https://github.com/SMTG-Bham/doped";
    changelog = "https://github.com/SMTG-Bham/doped/blob/main/CHANGELOG.rst";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
