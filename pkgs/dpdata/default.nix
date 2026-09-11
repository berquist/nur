{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  h5py,
  lmdb,
  msgpack,
  numpy,
  pyyaml,
  scipy,
  wcmatch,

  # tests
  pytestCheckHook,
  ase,
  dpdata-plugin-test,
  openbabel-bindings,
  parmed,
  pymatgen,
  rdkit,
}:

# dpdata — DeepModeling's format converter: it reads and writes the trajectory
# and label formats of VASP, Quantum ESPRESSO, LAMMPS, ABACUS, CP2K, Gaussian,
# ORCA, Amber, GROMACS and a dozen more, and converts between them.  Here for
# ../deepmd-kit, which names it in both its `test` and its `dpa-adapt` extras
# and registers a `dpdata.plugins` entry point into it.  Internal, not
# re-exported.
buildPythonPackage (finalAttrs: {
  pname = "dpdata";
  version = "1.1.0";
  pyproject = true;
  __structuredAttrs = true;

  # The tag and the repository HEAD are the same commit, which is unusual enough
  # in this part of the tree to be worth saying.
  src = fetchFromGitHub {
    owner = "deepmodeling";
    repo = "dpdata";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uFkR1v7itqOMkFHfZ+cSHkmYtTb5fN5nsTutmxzq5Og=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # setuptools-scm with no repository to read.  It is `write_to` here rather
  # than a plain version, so without the pin the generated `dpdata/_version.py`
  # carries a `0.1.dev1` that then shows up in `dpdata --version`.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # **`lmdb>=2.0.0` relaxed, and this is the one relaxation here that argues
  # against a bound rather than around it.**  The materials overlay pins py-lmdb
  # *down* to 1.7.3, because 2.0.0 made a second `open()` of an already-open
  # environment path an error and three packages here depend on doing exactly
  # that — see the `lmdb` binding in ../../overlays.  So this floor and that pin
  # cannot both be honoured in one package set.
  #
  # Relaxing is the right way round of the two, because the *library* is written
  # for 2.0's restriction rather than against it: `formats/deepmd/lmdb/format.py`
  # keeps a module-level `_READ_ENV_CACHE` keyed by path precisely so it never
  # opens one twice.  Code that careful about not reopening runs unchanged on
  # the version that would have allowed it.  Nothing in that module reads
  # `lmdb.version()` or branches on it, and there is no 2.x-only call in it.
  #
  # The floor is also softer than it looks: upstream made the whole plugin
  # optional in 991a38d, "chore(lmdb): allow missing LMDB imports", which is this
  # very tag — `plugins/lmdb.py` catches `ModuleNotFoundError` for lmdb and
  # msgpack and defers the failure to first use of the format.  A declared floor
  # on a dependency that need not be installed at all is a preference.
  #
  # **It is not free, though, and the first build said so.**  Three tests in
  # `test_lmdb.py` assert that a second open *raises*, which is 2.0 behaviour and
  # not 1.7.3's, so the error-handling paths do depend on the bound even though
  # the reader does not.  They are deselected, and `disabledTests` below carries
  # the detail.  Read that before believing this paragraph on its own.
  pythonRelaxDeps = [ "lmdb" ];

  dependencies = [
    h5py
    lmdb
    msgpack
    numpy
    pyyaml
    scipy
    wcmatch
  ];

  # The three formats whose readers are third-party: `plugins/ase.py`,
  # `plugins/pymatgen.py` and the bond-order plugin's rdkit.  All optional at
  # run time — each plugin module is imported lazily through the format
  # registry — so they are check inputs rather than dependencies, which is also
  # how upstream declares them (`ase`, `pymatgen` and the rdkit-carrying `docs`
  # extra).
  #
  # `openbabel-bindings` is not optional the way its import sites suggest.
  # Every `from openbabel import openbabel` in the library is function-local,
  # and `tests/test_gaussian_driver.py` skips itself without it — so reading the
  # source says "optional".  `tests/test_gaussian_gjf.py` says otherwise: it
  # calls the gjf writer, which reaches openbabel to perceive bonds, and it
  # carries no guard at all.  Twelve failures, all
  # `ModuleNotFoundError: No module named 'openbabel'`.
  #
  # `parmed` is ../parmed, packaged for this one dependant: `TestPickByAmberMask`
  # in `test_pick_atom_idx.py` was deselected for want of it, and the class it
  # sits beside — `TestPickAtomIdx` — needs none of it.  Upstream declares it
  # under both the `amber` extra and the `test` one.  Note the module would not
  # even *skip* without it; see the upstream guard bug in the note at
  # `disabledTests`.
  #
  # `dpdata-plugin-test` is the fixture distribution out of this repository's own
  # `tests/plugin/`, and it has to be *installed* rather than imported — the
  # header of ../dpdata-plugin-test explains why an import is too late.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    dpdata-plugin-test
    openbabel-bindings
    parmed
    pymatgen
    rdkit
  ];

  # One flag, and it exists to make pytest behave like the `python -m unittest`
  # upstream actually runs.  This suite is built on
  # mixins that are named `Test*` but do not inherit `unittest.TestCase` —
  # `TestPOSCARoh`, `TestTypeMap`, `TestFhi_aims`, `TestSIESTASinglePointEnergy`
  # and a dozen more — which real cases then combine, as in
  # `class TestPOSCARDump(unittest.TestCase, TestPOSCARoh)`.  unittest's loader
  # only collects `TestCase` subclasses, so it never sees the mixins.  pytest's
  # default `python_classes = Test*` collects them all and runs their inherited
  # test methods against a `self` that has no `assertEqual` — about 155 failures
  # reading `AttributeError: 'TestPOSCARoh' object has no attribute
  # 'assertEqual'`, none of which is a defect in dpdata.
  #
  # Emptying `python_classes` collects no class by name, and pytest collects
  # `unittest.TestCase` subclasses regardless of this setting, so what is left is
  # exactly unittest's own view.  Verified on a two-class reproduction before
  # being written here.
  #
  pytestFlags = [ "--override-ini=python_classes=" ];

  # Two lines, and they are two different problems that both involve
  # `tests/context.py`.
  #
  # **The `rm` is the shadowing trap, in its most explicit form.**  `context.py`
  # does `sys.path.insert(0, <repository root>)` and then `import dpdata`, and
  # 93 of the 108 test modules import it — so every one of them would test the
  # unpacked source rather than what was just installed, and a packaging error
  # in the wheel would go unnoticed.  Deleting the source copy makes that insert
  # point at a directory with no `dpdata` in it, and the import falls through to
  # site-packages.  ../sella and ../wignernj carry the same line for the same
  # reason, and ../trexio a two-level-deep version of it.  This one is the least
  # subtle of the four and the easiest to leave in place by accident, because
  # nothing fails when you do.
  #
  # **The `cd` is what makes `context` importable at all, and it is upstream's
  # own invocation.**  `.github/workflows/test.yml` runs
  # `cd tests && coverage run --source=../dpdata -m unittest`, and the working
  # directory is load-bearing twice over:
  #
  #   `tests/poscars/test_lammps_dump_s_su.py` is the one module in a
  #   subdirectory that does `from context import dpdata`.  pytest's default
  #   `prepend` import mode puts that module's own basedir — `tests/poscars/`,
  #   there being no `__init__.py` — on `sys.path`, not `tests/`, so `context`
  #   is not found and **the whole run aborts on the collection error**, 2528
  #   collected items and all.  Running from `tests/` puts it on `sys.path` as
  #   the working directory instead, which is what upstream relies on.
  #
  #   Every fixture path in the suite is relative to `tests/` —
  #   `dpdata.LabeledSystem("amber/02_Heat", fmt="amber/md")` and a hundred
  #   like it.
  #
  # No `enabledTestPaths`, deliberately: with the working directory inside the
  # suite, pytest collects it whole, and the usual glob-matches-nothing canary
  # would be a `.` that always matches.  `cd tests` under `set -e` is the guard
  # that actually fires if the directory ever stops being there.
  #
  # **`$out/bin` on PATH** for `test_cli.py`, which drives the installed console
  # script through `subprocess` and errors with a bare
  # `FileNotFoundError: [Errno 2] No such file or directory: 'dpdata'` without
  # it — six errors, and nothing in the message says "PATH".  ../aiida-gromacs
  # and ../aiida-pseudo carry the same line.
  preCheck = ''
    rm -rf dpdata
    cd tests

    export PATH="$out/bin:$PATH"
  '';

  # Three tests, all of them `test_lmdb.py`'s, and they are **the cost of the
  # `lmdb` relaxation above, which is not free after all.**  Each asserts that
  # opening an environment a second process already holds raises — which is
  # exactly the behaviour py-lmdb introduced in 2.0.0 and this repository pins
  # *down* to 1.7.3 to avoid.  On 1.7.3 the second open succeeds, so
  # `assertRaises(LMDBError)` sees nothing raised and the race guard reports
  # `[False] != [True]`.
  #
  # So the reasoning at `pythonRelaxDeps` is right about the library — the reader
  # caches environments by path and never needs the guard — and wrong that
  # nothing depends on it: the *error handling* does, and these three tests are
  # what prove it.  They come back the day py-lmdb 2.x can be unpinned; the
  # standing item is in ../../docs/TODO.md.
  #
  # `TestPickByAmberMask` used to be a fourth entry and is not any more, ../parmed
  # having been packaged for it.  Worth knowing what it will look like if it ever
  # fails again, because the module cannot skip itself: upstream's guard is
  #
  #     try:
  #         exist_module = True
  #     except Exception:
  #         exist_module = False
  #
  # — an empty `try` that lost its `import parmed`, so `exist_module` is always
  # True, `@unittest.skipIf(not exist_module)` never fires, and `setUp` reaches a
  # name that may never have been imported.  A missing parmed shows up as
  # `NameError`, not as a skip.
  disabledTests = [
    "test_existing_external_reader_has_actionable_error"
    "test_external_lmdb_reader_blocks_overwrite"
    "test_publish_guard_closes_external_reader_race"
  ];

  pythonImportsCheck = [
    "dpdata"
    "dpdata.cli"
    "dpdata.plugins"
    "dpdata.system"
  ];

  meta = {
    description = "Manipulate data formats of DeePMD-kit, VASP, LAMMPS, Quantum ESPRESSO and others";
    homepage = "https://github.com/deepmodeling/dpdata";
    changelog = "https://github.com/deepmodeling/dpdata/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.lgpl3Plus;
    mainProgram = "dpdata";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
