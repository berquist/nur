{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  setuptools,
  setuptools-scm,

  # nativeBuildInputs
  glibcLocales,

  # dependencies
  bibtexparser,
  joblib,
  lxml,
  matplotlib,
  monty,
  networkx,
  numpy,
  orjson,
  palettable,
  pandas,
  plotly,
  requests,
  scipy,
  spglib,
  sympy,
  tabulate,
  tqdm,
  uncertainties,

  # optional-dependencies
  ase,
  beautifulsoup4,
  f90nml,
  h5py,
  moyopy,
  netcdf4,
  numba,
  phonopy,
  seekpath,

  # tests
  pytest-xdist,
  pytestCheckHook,
}:

# One half of upstream's 2026 split, and the half that holds the code.
#
# `pymatgen` used to be one distribution.  From 2026.7.16 the core -- core, io,
# symmetry, transformations, util, alchemy, command_line, electronic_structure,
# optimization, phonon, and the three phase-diagram modules of analysis -- lives
# in its own repository and ships as `pymatgen-core`; what is left in
# `pymatgen` is analysis, apps, cli, entries, ext and vis, plus a dependency on
# this.  See ../pymatgen for that half.
#
# **This replaces nixpkgs' `pymatgen`; it cannot sit beside it.**  Both own the
# `pymatgen/...` import paths, so any environment holding nixpkgs' 2025.10.7
# monolith and this at once has two copies of `pymatgen.core` fighting over one
# directory.  That is why ../../overlays/default.nix injects both halves into
# the materials overlay's package-set extension rather than binding them
# locally the way `pymatgenFor` binds its repaired monolith -- an override can
# be kept invisible to the rest of a consumer's set, but a *replacement* of a
# name the consumer already has cannot be.
#
# The two distributions are PEP 420 namespace packages: neither ships
# `pymatgen/__init__.py`, and no installed file path appears in both, so
# `python3.withPackages` merges them without a collision.  `pymatgen/analysis`
# is the one directory they share, and they share it the way a namespace
# package is meant to be shared -- three modules from here, the rest from
# there, no `__init__.py` on either side.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-core";
  version = "2026.8.13";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pymatgen-core";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kq1mxaLjhuC+AWe/hZ4Rdtcw0M5dkKQ3pWtWV+Yhq2Y=";
  };

  # `pmg` is not in this distribution and has not been since the split: the
  # entry point names `pymatgen.cli.pmg:main`, and `pymatgen/cli` went to the
  # other repository along with the rest of the command-line front end.  What
  # upstream leaves behind is a console script that raises ModuleNotFoundError
  # the moment it is run.
  #
  # Deleting it is not tidiness.  ../pymatgen declares a `pmg` of its own that
  # does work, and both halves are meant to be installed together, so leaving
  # this one in place puts two different `$out/bin/pmg` into one
  # `python3.withPackages` and buildEnv refuses the environment outright.
  #
  # Reported upstream as materialsproject/pymatgen-core; drop this once the
  # entry point goes.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[project.scripts]
    pmg = "pymatgen.cli.pmg:main"

    ' \
        ""
  '';

  # setuptools_scm reads the version from git and fetchFromGitHub hands over a
  # tarball with no repository.  Same shape as ../maggma, and derived from
  # `version` rather than repeated so the two cannot drift.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    cython
    setuptools
    setuptools-scm
  ];

  # setup.py builds three Cython extensions -- coord_cython, neighbors and
  # fast_parser -- and reaches for `numpy.get_include()` while doing it, which
  # the propagated `numpy` below covers.  glibcLocales is inherited from
  # nixpkgs' pymatgen derivation, where it is what keeps the CIF and structure
  # readers from tripping over an ASCII default locale.
  nativeBuildInputs = [ glibcLocales ];

  # lxml is new in the split (io/vasp and io/cif parse with it now) and pybtex
  # is gone: `pymatgen.io.cif` reads BibTeX through bibtexparser alone, so the
  # `pybtex` nixpkgs' derivation carries has no importer left.
  dependencies = [
    bibtexparser
    joblib
    lxml
    matplotlib
    # >= 2026.7.16, which no channel in ../../Justfile's `channels` carries.
    # See ../monty for why that is a package of ours rather than a relaxed pin.
    monty
    networkx
    numpy
    orjson
    palettable
    pandas
    plotly
    requests
    scipy
    spglib
    sympy
    tabulate
    tqdm
    uncertainties
  ];

  # Two floors that only the nixos-26.05 leg misses, and both by a hair:
  #
  #     Checking runtime dependencies for pymatgen_core-2026.8.13-*.whl
  #       - lxml>=6.1.0 not satisfied by version 6.0.2
  #       - tqdm>=4.67.3 not satisfied by version 4.67.1
  #
  # pythonRuntimeDepsCheckHook fails the wheel there, before a single test
  # runs.  The two unstable legs carry lxml 6.1.1 and tqdm 4.68.4 and are
  # unaffected, so this is the same 26.05-only shape as ../monty -- and unlike
  # ../monty's `monty>=2026.7.16`, these two really are relaxable.
  #
  # What upstream actually uses of either is old, ordinary API.  All of the
  # lxml is in `io/vasp/outputs.py`, the one module that imports it, and it
  # reaches for exactly three names -- `etree.iterparse` (with `events=` and
  # `tag=`), `etree.XMLSyntaxError`, and `etree.Element` as a type annotation.
  # tqdm is a progress bar in five modules: construction, `disable=`, `desc=`,
  # `unit=`, `total=`, `.update()` and `.close()`.  Nothing there postdates
  # lxml 6 or tqdm 4.60, let alone the two patch releases between 4.67.1 and
  # 4.67.3, so the floors read as "whatever was current when the pin was last
  # touched" rather than as a feature requirement.
  #
  # Relaxed unconditionally rather than guarded on the channel's version: the
  # rewrite only drops the declared floor from the wheel's metadata, and where
  # the channel is already new enough the installed version satisfies it
  # anyway, so a guard would buy nothing but eval complexity.  Drop both once
  # 26.05 leaves ../../Justfile's `channels`.
  pythonRelaxDeps = [
    "lxml"
    "tqdm"
  ];

  # `vis` is deliberately absent, unlike nixpkgs' pymatgen: `pymatgen.vis` and
  # its vtk requirement went to ../pymatgen with the rest of the front end.
  #
  # `matcalc`, `mlp`, `tblite` and `zeopp` are absent for the ordinary reason --
  # matcalc, matgl and pyzeo are in no channel here, and upstream gates the
  # first three on `python_version < '3.13'` anyway, which this repo's pin is
  # not.  `optional` drops `hiphive` for the same reason and keeps the rest.
  optional-dependencies = {
    abinit = [ netcdf4 ];
    ase = [ ase ];
    numba = [ numba ];
    symmetry = [ moyopy ];
    optional = [
      ase
      beautifulsoup4
      f90nml
      h5py
      netcdf4
      phonopy
      seekpath
    ];
  };

  # Every optional dependency this repo can reach, because the suite gates all
  # of them behind `pytest.importorskip` rather than a hard requirement --
  # leaving one out is a silent loss of coverage, not a failure.  moyopy alone
  # is worth several hundred symmetry assertions.
  #
  # pytest-xdist is not optional here: `[tool.pytest.ini_options]` in
  # pyproject.toml opens with `addopts = "-n auto ..."`, so without the plugin
  # pytest aborts on an unrecognised argument before collecting anything.
  # nixpkgs' setup hook then appends `--numprocesses=$NIX_BUILD_CORES`, which
  # wins over the `-n auto`.
  nativeCheckInputs = [
    pytest-xdist
    pytestCheckHook
  ]
  ++ finalAttrs.passthru.optional-dependencies.numba
  ++ finalAttrs.passthru.optional-dependencies.symmetry
  ++ finalAttrs.passthru.optional-dependencies.optional;

  # HOME in preBuild rather than preCheck, the same reasoning as ../aiida-core
  # and ../pymatgen: matplotlib creates $HOME/.config/matplotlib on import, and
  # the default /homeless-shelter is not writable, so `pythonImportsCheck` -- a
  # different phase, running before the tests -- prints
  #
  #     mkdir -p failed for path /homeless-shelter/.config/matplotlib
  #
  # and falls back to a temporary cache.  genericBuild runs every phase in one
  # shell, so exporting it once, early, covers the import check and the suite
  # both.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # `pymatgen.util.testing` resolves TEST_FILES_DIR relative to the *installed*
  # package -- `f"{ROOT}/../test-files"` -- which points into $out, where the
  # 248 MB of fixtures deliberately are not.  PMG_TEST_FILES_DIR is the
  # documented override and the only thing standing between the suite and a few
  # thousand FileNotFoundErrors.
  #
  # MPLBACKEND for the plotters, which otherwise try to autodetect a display.
  preCheck = ''
    export PMG_TEST_FILES_DIR="$(realpath ./test-files)"
    export MPLBACKEND=Agg
  '';

  pythonImportsCheck = [
    "pymatgen.core"
    "pymatgen.core.structure"
    "pymatgen.io.vasp"
    "pymatgen.symmetry.analyzer"
    # The three Cython extensions, which import cleanly only if they were
    # actually compiled and installed.
    "pymatgen.optimization.neighbors"
    "pymatgen.optimization.fast_parser"
    "pymatgen.util.coord_cython"
  ];

  meta = {
    description = "Core data structures and algorithms of Python Materials Genomics";
    homepage = "https://pymatgen.org/";
    changelog = "https://github.com/materialsproject/pymatgen-core/blob/v${finalAttrs.version}/CHANGES.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
