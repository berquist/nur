{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  setuptools,
  setuptools-scm,

  # dependencies
  pymatgen-core,

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
  spglib,
  vtk,

  # tests
  pytest-xdist,
  pytestCheckHook,
  openbabel,
}:

# The other half of upstream's 2026 split, and the half that keeps the name.
#
# What is left in the `pymatgen` distribution after the core moved out is
# analysis (everything but the three phase-diagram modules), apps, cli, entries,
# ext and vis -- roughly the parts that consume ../pymatgen-core rather than
# implement it.  `dependencies` really is just the one entry: upstream's own
# pyproject.toml declares nothing else, because everything either half needs is
# propagated by the core.
#
# Read ../pymatgen-core's header first.  It carries the part that matters --
# why the pair replaces nixpkgs' pre-split monolith rather than sitting beside
# it, and why the two distributions can share the `pymatgen/` tree without
# colliding in a `withPackages` environment.
#
# This is what `emmet-core` and `atomate2` mean when they ask for `pymatgen`,
# and both also ask for `pymatgen-core` by name, which is the reason neither
# half is optional here.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen";
  version = "2026.5.4-unstable-2026-08-27";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v2026.5.4 tag, which is nearly four months and
  # sixty-eight commits behind it.  The tag would install -- it asks only for
  # `pymatgen-core>=2026.4.16` and gets 2026.8.13 -- but upstream moved its own
  # floor to `>=2026.7.16` after the tag ("algin toml wth core"), and the
  # commits in between include "Update docs and fix tests" and "Fix failing
  # test" against exactly that newer core.  Pinning the tag would mean shipping
  # the one pairing upstream has never run its suite against.
  #
  # .gitmodules carries `pymatgen-core` as a submodule, which fetchSubmodules
  # leaves as an empty directory.  That is correct and not an oversight: the
  # submodule is how upstream builds its documentation from both halves at
  # once, and `[tool.setuptools.packages.find]` looks in `src` alone.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pymatgen";
    rev = "b6cca4524e24800e6ed3dc48c6294bcca91a7329";
    hash = "sha256-B8yGL99ix5TZamlyq76PABweqW//3Z2S/wJ/3F8hgLo=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository, the
  # same hole ../maggma falls into.  What it cannot take is the `-unstable-`
  # suffix above, which is a nixpkgs convention rather than a PEP 440 version
  # and makes setuptools reject the metadata outright, so the part before the
  # first dash is what goes in: the last tag, which is what upstream's own
  # `version_scheme = "no-guess-dev"` would report as the base anyway.
  #
  # Derived rather than repeated so the two cannot drift, the same way
  # ../sella derives its own.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  # Cython is listed because pyproject.toml's `[build-system] requires` still
  # names it, left over from before the split -- setup.py and the three .pyx
  # files went to ../pymatgen-core, and this half is pure Python.  It is not
  # dead weight all the same: nixpkgs builds with `--no-isolation`, and
  # pypaBuildPhase checks the declared build requirements against what is
  # actually installed before it starts.  Leaving it out fails the build before
  # the wheel exists:
  #
  #     ERROR Unmet dependencies ...
  #       Cython>=0.29.23
  #         wanted: >=0.29.23
  #         found: not installed
  #
  # The `numpy>=2.1.0` in the same list needs nothing: ../pymatgen-core
  # propagates it.
  build-system = [
    cython
    setuptools
    setuptools-scm
  ];

  dependencies = [ pymatgen-core ];

  # Upstream's extras, minus the ones no channel here can satisfy: `matcalc`
  # and `mlp` (matcalc, matgl -- and gated on `python_version < '3.13'`, which
  # this repo's pin is not), `prototypes` (pyxtal), `zeopp` (pyzeo), and the
  # chemview/galore/hiphive/jarvis-tools/pymatgen-analysis-alloys members of
  # `optional`.
  #
  # `vis` is the one that is here and not in ../pymatgen-core: `pymatgen.vis`
  # is in this half, so vtk belongs to this half too.
  optional-dependencies = {
    abinit = [ netcdf4 ];
    ase = [ ase ];
    numba = [ numba ];
    symmetry = [
      moyopy
      spglib
    ];
    vis = [ vtk ];
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

  # Everything reachable, because the suite gates each of them behind
  # `pytest.importorskip`.  vtk is the one worth naming: without it the whole
  # of tests/vis skips, and so does `test_pmg_view`, which is the only coverage
  # the `pmg view` subcommand has.
  #
  # pytest-xdist is not in this half's `addopts` the way it is in
  # ../pymatgen-core's -- upstream commented the `-n auto` out here -- but the
  # nixpkgs setup hook still supplies `--numprocesses=$NIX_BUILD_CORES`, and
  # this suite is large enough to want it.
  nativeCheckInputs = [
    pytest-xdist
    pytestCheckHook
    openbabel
  ]
  ++ finalAttrs.passthru.optional-dependencies.numba
  ++ finalAttrs.passthru.optional-dependencies.symmetry
  ++ finalAttrs.passthru.optional-dependencies.vis
  ++ finalAttrs.passthru.optional-dependencies.optional;

  # This half ships its own `test-files`, disjoint from the core's, and the
  # tests reach it two ways: `tests/testing.py` resolves it relative to the
  # test tree, and `pymatgen.util.testing` -- which lives in the core -- resolves
  # it relative to the *installed* core package, where it is not.
  # PMG_TEST_FILES_DIR is the documented override for the second.
  #
  # The three ext modules need no network handling: tests/ext/test_cod.py skips
  # itself unconditionally, and test_matproj.py and test_optimade.py both gate
  # on a probe that raises ConnectionError immediately in a build sandbox.
  preCheck = ''
    export PMG_TEST_FILES_DIR="$(realpath ./test-files)"
    export MPLBACKEND=Agg
    export HOME="$(mktemp -d)"
  '';

  pythonImportsCheck = [
    "pymatgen.analysis.local_env"
    "pymatgen.apps.borg.hive"
    "pymatgen.cli.pmg"
    "pymatgen.entries.compatibility"
    "pymatgen.ext.matproj"
    # Not pymatgen.vis: structure_vtk imports vtk at module scope, and vtk is
    # an optional dependency rather than a propagated one.
  ];

  meta = {
    description = "Robust materials analysis code that defines core object representations for structures and molecules";
    homepage = "https://pymatgen.org/";
    changelog = "https://github.com/materialsproject/pymatgen/releases";
    license = lib.licenses.mit;
    mainProgram = "pmg";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
