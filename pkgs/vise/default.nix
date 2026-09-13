{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  boltztrap2,
  matplotlib,
  monty,
  more-itertools,
  mp-api,
  num2words,
  numpy,
  pandas,
  phonopy,
  pymatgen-core,
  pyyaml,
  scipy,
  seekpath,
  spglib,
  tabulate,
  tqdm,

  # tests
  pytestCheckHook,
  pytest-mock,
  pytest-xdist,
}:

# vise — VASP input-set generation and output analysis from the Kumagai group.
#
# Packaged for the `quacc[defects]` chain rather than for itself: `doped` needs
# it for eigenvalue analysis and `pydefect` is built on it outright.  It is a
# usable tool in its own right, though — two console scripts and no dependency
# on anything unpackaged — so it is re-exported rather than kept internal.  See
# "Deferred packaging" in ../../AGENTS.md for the rest of that cluster.
buildPythonPackage {
  pname = "vise";
  version = "0.9.5-unstable-2026-05-14";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD, 827 commits past the v0.1.13 tag — upstream tags rarely and the tag is
  # from 2020.  This particular commit is the merge of `pmg-core-refactoring`,
  # which is what makes vise import from pymatgen's 2026 split; anything older
  # expects the pre-split monolith that this repo no longer carries.
  src = fetchFromGitHub {
    owner = "kumagai-group";
    repo = "vise";
    rev = "19bc8c4582109201ac2e3faf6e69d985ab85d494";
    hash = "sha256-k+dBi1hnziK2dXN8Rp3u/o5dkCg09eEIhjUXyMJw7hU=";
  };

  # Two dead imports of `distutils`, which Python removed in 3.12.  Neither name
  # is ever used: `str_related_tools` imports `strtobool` and then defines its
  # own `str2bool` beside it, and `setup.py` imports `Extension` while leaving
  # `ext_modules` empty.
  #
  # Both happen to work today only because setuptools ships a `distutils` shim
  # and installs it through a `.pth` file — which covers the build, where
  # setuptools is present by construction, but not a runtime environment that
  # has no reason to carry it.  Deleting the lines is the whole fix.
  postPatch = ''
    substituteInPlace vise/util/str_related_tools.py \
      --replace-fail 'from distutils.util import strtobool' ""

    substituteInPlace setup.py \
      --replace-fail 'from distutils.extension import Extension' ""
  '';

  build-system = [ setuptools ];

  # `setup.py` reads requirements.txt, which names six: pymatgen-core, seekpath,
  # num2words, more_itertools, phonopy and mp-api.  The rest below are imported
  # by `vise/` and declared by nobody — matplotlib, monty, numpy, pandas, scipy,
  # spglib, tabulate, tqdm and yaml.  Each arrives transitively through
  # pymatgen-core or phonopy today, so listing them costs no closure; it costs
  # nothing and stops the day one of those drops a dependency of its own.  Same
  # reasoning as ../ccreg's undeclared three.
  #
  # boltztrap2 is the load-bearing one, and belongs here rather than among the
  # check inputs it first looked like.  `vise/util/phonopy/phonopy_input.py`
  # imports `pymatgen.electronic_structure.boltztrap2` at *module* scope and
  # raises `Calculating effective mass requires BoltzTrap2` when it is missing;
  # `vise/cli/main_util.py` imports through that module, so the `vise_util`
  # console script does not start without it.  `vise.cli.main_util` is in
  # `pythonImportsCheck` below for exactly that reason — the first version of
  # this derivation checked `vise.cli.main` alone and the import check passed
  # while half the suite failed to collect.
  dependencies = [
    boltztrap2
    matplotlib
    monty
    more-itertools
    mp-api
    num2words
    numpy
    pandas
    phonopy
    pymatgen-core
    pyyaml
    scipy
    seekpath
    spglib
    tabulate
    tqdm
  ];

  # pytest-mock supplies the `mocker` fixture that thirty-seven tests want.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mock
    pytest-xdist
  ];

  # Twenty-three tests need a VASP licence, so they are dropped.
  #
  # They do not run VASP — nothing in this suite does.  What they need is VASP's
  # POTCAR files: the pseudopotential data that ships with the program, under
  # the same licence, and that nobody may redistribute.  vise builds an INCAR
  # partly from what it reads out of them, so any test that generates real input
  # files has to open one.
  #
  # Upstream works around that by committing stand-ins under
  # `test_data_files/fake_potcars` — real POTCARs with everything but a few
  # header lines stripped out, by a `create_fake_potcar.sh` sitting beside them.
  # That was enough when they were written.  It is not any more: pymatgen now
  # validates a POTCAR as it reads it, and validation looks at the numerical
  # block the stripping removed, so every one of them is rejected.  Only a real
  # POTCAR will do, and having one means having VASP.
  #
  # Hence no `PMG_VASP_PSP_DIR` either, though the suite asks for it.  Pointing
  # it at the stand-ins was tried: the same twenty-three tests fail, one step
  # later, with a complaint about the stripped file instead of a missing
  # directory.  Configuration that moves an error without fixing a test is worse
  # than none.
  #
  # Three of the four modules below go wholesale — 15, 2 and 1 tests, every one
  # of them a POTCAR reader.  `test_potcar_generator.py` is not here because one
  # of its five, `test_not_exist`, passes precisely by checking that a *missing*
  # POTCAR is reported; its other four are named below, as is the single one in
  # `test_dataset_util.py`.
  disabledTestPaths = [
    "vise/tests/input_set/test_incar_settings_generator.py"
    "vise/tests/input_set/test_vasp_input_files.py"
    "vise/tests/util/test_valence_orbitals_from_potcar.py"

    # Nothing to do with VASP: these two are written against an older phonopy
    # than nixpkgs has, and call a method and a constructor argument that
    # phonopy has since removed.  vise itself does not use either — only these
    # tests do, poking at the structure-conversion helper directly.
    "vise/tests/util/phonopy/test_phonopy_input.py"
  ];

  disabledTests = [
    # Both fetch a structure from api.materialsproject.org.
    "test_get_poscar_from_mp"
    "test_get_poscar_from_mp_by_formula"

    # References test_data_files/MgSe_band_noncollinear_vasprun.xml, which
    # upstream never committed — the only test here that is simply missing its
    # input rather than its environment.
    "test_band_edge_properties_from_vasp_non_collinear"

    # The remaining POTCAR readers, named one by one because the modules they
    # sit in also hold tests that pass.  See the note above `disabledTestPaths`.
    # Each name occurs once in the suite and none is a prefix of another, which
    # matters: `disabledTests` matches on substrings.
    "test_nbands"
    "test_normal_mg"
    "test_mp_relax_set_mg"
    "test_gw"
    "test_normal_largest_z"
  ];

  # The suite lives inside the package, at `vise/tests`, and is named
  # explicitly so that it is obvious it ran — a glob matching nothing is fatal,
  # which is the canary ../../AGENTS.md asks for.  Its 65 MB of reference
  # vasprun.xml, PROCAR and OUTCAR files come along in `src` but are installed
  # by neither MANIFEST.in nor package_data, so the output does not carry them.
  #
  # Most of it runs on that reference data alone.  The exception is the
  # twenty-three tests that need VASP's own pseudopotential files, which is what
  # `disabledTestPaths` and `disabledTests` below are mostly about.
  enabledTestPaths = [ "vise/tests" ];

  pythonImportsCheck = [
    "vise"
    "vise.analyzer"
    "vise.cli.main"
    # Both console scripts, and this is the one that reaches boltztrap2 — see
    # the note above `dependencies`.
    "vise.cli.main_util"
    "vise.input_set"
    "vise.util.phonopy.phonopy_input"
  ];

  meta = {
    description = "VASP input-set generation and output analysis";
    homepage = "https://github.com/kumagai-group/vise";
    license = lib.licenses.mit;
    mainProgram = "vise";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
