{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  adjusttext,
  emmet-core,
  matplotlib,
  matplotlib-label-lines,
  monty,
  mp-api,
  numpy,
  pandas,
  pymatgen-core,
  pyyaml,
  ruamel-yaml,
  scikit-image,
  scipy,
  tabulate,
  vise,

  # tests
  joblib,
  pytestCheckHook,
  pytest-mock,
  pytest-xdist,
}:

# pydefect — first-principles point-defect calculations, from the Kumagai group
# and built on ../vise.  Here for `doped`, which uses it for eigenvalue analysis,
# and through doped for `shakenbreak` and `quacc[defects]`.  Internal, not
# re-exported — see "Deferred packaging" in ../../AGENTS.md.
buildPythonPackage {
  pname = "pydefect";
  version = "0.10.1-unstable-2026-05-25";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD, 764 commits past the v0.2.6 tag — the same tagging habit as ../vise,
  # whose note explains the arrangement.  `pydefect/__init__.py` carries the
  # real version, 0.10.1, and `setup.py` reads it from there.
  src = fetchFromGitHub {
    owner = "kumagai-group";
    repo = "pydefect";
    rev = "a47f661b6999122e3bf6ba36682eae5546f71de6";
    hash = "sha256-Gf9jaYEieUPvMDhh2cvJz4ztlHXvPavt8CEixzYSggI=";
  };

  # pydefect's Mpl plotters draw onto pyplot's *current* axes — none of them
  # calls `plt.figure()` — and nothing in the suite ever closes a figure, so one
  # test inherits whatever the last one left behind.  When that is
  # `chem_pot_diag/cpd_plotter.py`'s three-dimensional diagram, the next
  # plotting test dies on a message about marker sizes:
  #
  #   ValueError: s must be float, but has type object
  #
  # which is `Axes3D.scatter` forwarding its own `s=None` default to
  # `Axes.scatter`, where a 2-D axes would have substituted the rcParam.  The
  # failure is a 3-D axes receiving a 2-D plot, not anything about sizes.
  #
  # Order-dependent, so a lottery under the pytest-xdist this package uses —
  # which test lands on which worker decides whether it fires at all.  The patch
  # closes every figure after each test, which removes the shared state rather
  # than the symptom.  See ../../.claude/worklog for the same shape in aiida.
  patches = [ ./close-figures-between-tests.patch ];

  build-system = [ setuptools ];

  # `setup.py` reads requirements.txt, which names eight: numpy, monty,
  # pymatgen-core, vise, tabulate, adjustText, matplotlib-label-lines and
  # scikit-image.  The other seven below are imported by `pydefect/` and declared
  # by nobody — emmet-core, matplotlib, mp-api, pandas, ruamel-yaml, scipy and
  # yaml.  ../vise has the same habit and the same treatment; see the note above
  # its `dependencies`.
  #
  # emmet-core is the one that would be missed: a single
  # `from emmet.core.summary import SummaryDoc` in
  # `cli/vasp/make_composition_energies_from_mp.py`, at module scope, so
  # `pydefect_vasp` does not start without it.
  #
  # scikit-image runs the other way — declared but imported only inside
  # `make_local_extrema.py`, behind a message telling the user to install it.
  # Kept because upstream declares it and `pythonRuntimeDepsCheckHook` checks
  # what is declared.
  dependencies = [
    adjusttext
    emmet-core
    matplotlib
    matplotlib-label-lines
    monty
    mp-api
    numpy
    pandas
    pymatgen-core
    pyyaml
    ruamel-yaml
    scikit-image
    scipy
    tabulate
    vise
  ];

  # MPLCONFIGDIR as well as HOME, and that is not belt and braces: the HOME
  # export alone did **not** hold here.  A build of this package still reported
  #
  #   mkdir -p failed for path /homeless-shelter/.config/matplotlib
  #
  # from pythonImportsCheckPhase, which runs long after `runHook preBuild` — so
  # matplotlib was reading the sandbox's own HOME at that point, not the one set
  # below.  Nothing in stdenv's setup or in any of the Python setup hooks
  # between the two phases reassigns HOME, so why it did not carry is not
  # established; what is established is that it did not.
  #
  # MPLCONFIGDIR is the variable matplotlib's own message asks for and the only
  # one it consults before falling back to `Path.home()`, so it settles the
  # question regardless.  The directory has to exist and be writable, hence the
  # mkdir rather than a bare `env` attribute pointing somewhere in the store.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export MPLCONFIGDIR="$HOME/.config/matplotlib"
    mkdir -p "$MPLCONFIGDIR"
  '';

  # joblib is imported by the tests alone.  pytest-mock supplies the `mocker`
  # fixture, which sixty-nine of them want — the same omission ../vise's first
  # build turned up, and with the same shape: without the plugin they are
  # collection errors rather than failures, so the count looks alarming and the
  # cause is one line.
  nativeCheckInputs = [
    joblib
    pytestCheckHook
    pytest-mock
    pytest-xdist
  ];

  disabledTests = [
    # Queries api.materialsproject.org — the name says so.
    "test_mp_actual_query"
  ];

  # The suite lives inside the package, as ../vise's does, and is named so that
  # it is obvious it ran.  14 MB of recorded VASP output under
  # `tests/cli/vasp/vasp_files` comes along in `src`; MANIFEST.in installs only
  # `*.yaml` and `POSCAR` files, so the output does not carry it.
  enabledTestPaths = [ "pydefect/tests" ];

  pythonImportsCheck = [
    "pydefect"
    "pydefect.analyzer"
    "pydefect.cli.main"
    "pydefect.cli.main_util"
    "pydefect.cli.vasp.main_vasp"
    "pydefect.cli.vasp.main_vasp_util"
    "pydefect.corrections"
    "pydefect.input_maker"
  ];

  meta = {
    description = "Integrated environment for first-principles point-defect calculations";
    homepage = "https://github.com/kumagai-group/pydefect";
    license = lib.licenses.mit;
    mainProgram = "pydefect";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
