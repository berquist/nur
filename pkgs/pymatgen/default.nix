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

  # tests/analysis/magnetism/test_heisenberg.py builds its `HeisenbergMapper`
  # objects once in `setup_class` and shares them across the class, but
  # `HeisenbergMapper.__init__` leaves `self.ex_params` as None -- only
  # `get_exchange()` fills it in.  So `test_get_igraph`, `test_heisenberg_model`
  # and `test_as_from_dict_round_trip` all read state that `test_exchange_params`
  # produced, and none of them says so.
  #
  # Serially that is invisible, because pytest runs the class in definition
  # order and `test_exchange_params` comes first.  Under xdist it is a coin
  # flip: the default `--dist load` hands out tests one at a time rather than
  # by class, every worker runs `setup_class` afresh, and a worker that draws
  # `test_get_igraph` without having drawn `test_exchange_params` gets
  #
  #     TypeError: argument of type 'NoneType' is not iterable
  #
  # at heisenberg.py:553.  It passed on one build here and failed on the next
  # with nothing changed between them but the deselection above shifting the
  # distribution.
  #
  # Computing the exchange in `setup_class` makes each fixture complete however
  # the tests are dealt out.  `get_exchange()` reads `self.ex_mat` and writes
  # `self.ex_params`, so calling it twice is harmless -- `test_exchange_params`
  # still calls it itself and still asserts on the returned value.
  #
  # `--dist loadscope` would also fix it, by keeping the class on one worker.
  # Not chosen: it constrains the scheduler for the whole suite to paper over
  # one class's coupling, and it leaves the coupling in place to be tripped
  # over again by the next test that gets added here.
  #
  # Appended with a semicolon rather than as a second line: the replacement
  # sits at an indentation of twelve inside a `for` body, and a multi-line
  # replacement cannot carry that through Nix's indented string, whose dedent
  # is computed over the whole literal.  The quiet failure mode is worse than a
  # syntax error -- `cls.hms.append(hm)` re-emitted at eight spaces is still
  # valid Python, but it falls out of the loop.
  postPatch = ''
    substituteInPlace tests/analysis/magnetism/test_heisenberg.py \
      --replace-fail \
        'hm = HeisenbergMapper(ordered_structures, energies, cutoff=5.0, tol=0.02)' \
        'hm = HeisenbergMapper(ordered_structures, energies, cutoff=5.0, tol=0.02); hm.get_exchange()'
  '';

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
  # of tests/vis skips.  It is here for those, not for `test_pmg_view` -- that
  # one needs a display on top of vtk, and is deselected below.
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

  # `pmg view` is the one subcommand that opens a window.  MPLBACKEND does not
  # reach it -- it goes to `pymatgen.vis.structure_vtk.StructureVis`, which is
  # VTK rather than matplotlib, and `StructureVis.__init__` builds a
  # `vtkRenderWindow` and calls `redraw()` on it before returning.  With no X
  # display and no GPU that is a **segfault**, not an exception: the xdist
  # worker dies outright and pytest reports `worker 'gwN' crashed`, which is
  # why nothing here can be caught or skipped from inside the test.
  #
  # Deselected by name rather than node id because `disabledTests` is what the
  # hook turns into `-k`, and `test_pmg_view` is unique across the suite.  A
  # `tests/cli/test_pmg.py::test_pmg_view` entry in `disabledTestPaths` would
  # be the ../maggma trap instead: a `::` in a path is silently ignored.
  #
  # This is not the vtk dependency being wrong.  vtk stays a check input --
  # dropping it would skip the whole of tests/vis as well, and those are
  # headless and pass.
  disabledTests = [ "test_pmg_view" ];

  # HOME in preBuild rather than preCheck, the same reasoning as ../aiida-core:
  # matplotlib creates $HOME/.config/matplotlib on import, and the default
  # /homeless-shelter is not writable, so `pythonImportsCheck` -- a different
  # phase, running before the tests -- prints
  #
  #     mkdir -p failed for path /homeless-shelter/.config/matplotlib
  #
  # and falls back to a temporary cache.  genericBuild runs every phase in one
  # shell, so exporting it once, early, covers the import check and the suite
  # both.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

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
