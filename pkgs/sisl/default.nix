{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,

  # build-system
  cython,
  numpy,
  scikit-build-core,
  setuptools-scm,

  # native build tools
  cmake,
  ninja,
  gfortran,

  # dependencies
  pyparsing,
  scipy,
  xarray,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "sisl";
  version = "0.16.4";
  pyproject = true;

  # The release tag, not the tip of main, and the difference is not cosmetic.
  # Four commits after v0.16.4 — "trying wheel for win", "fixing windows wheel
  # creation", "trying fortran for win", "trying to fix coverage" — are an
  # unfinished Windows experiment, and one of them adds
  #
  #   set(CMAKE_SHARED_MODULE_SUFFIX ".${SKBUILD_SOABI}${CMAKE_SHARED_MODULE_SUFFIX}")
  #
  # to CMakeLists.txt while every extension is still built with
  # `python_add_library(... WITH_SOABI ...)`, which appends the same suffix
  # itself.  Every module then installs twice-suffixed —
  # `_indices.cpython-313-x86_64-linux-gnu.cpython-313-x86_64-linux-gnu.so` —
  # so the build succeeds and the import fails:
  #
  #   ModuleNotFoundError: No module named 'sisl._indices'
  #
  # The block does not exist at the tag.
  #
  # The hash is also the reason to prefer the tag.  `.gitattributes` marks
  # CITATION.cff, pyproject.toml and .git_archival.txt `export-subst`, whose
  # `$Format:...$` placeholders expand at archive time and do not agree between
  # a local clone and GitHub: on main the describe-name abbreviates to ten hex
  # characters there and nine here, and ref-names lists the local branches.  At
  # a tag both are exact — `describe-name: v0.16.4`, `ref-names: tag: v0.16.4`
  # — so scripts/offline-src-hash.sh can compute it after all.  It still warns,
  # correctly, that it cannot promise that; if this ever mismatches, take the
  # value the build prints.
  #
  # `fetchSubmodules` is deliberately left at its default of false.  The one
  # submodule, `files`, is zerothi/sisl-files — a separate repository of
  # reference output from Siesta, TranSiesta and friends, used only by tests
  # that ask for the `sisl_files` fixture.  src/sisl/conftest.py xfails exactly
  # those when SISL_FILES_TESTS is unset, which is the state here, so fetching
  # it would add a large download and change nothing that runs.
  src = fetchFromGitHub {
    owner = "zerothi";
    repo = "sisl";
    tag = "v${version}";
    hash = "sha256-AfFv1J9brJkov9j8xVa14q3cXJKqE7WaT6YEgpAp5ww=";
  };

  # The tag predates `f17c6bc4b Fix build failure with scikit-build-core >= 0.10`,
  # so its `[tool.scikit-build]` still says `cmake.verbose`, and 1.0.2 refuses
  # to read the file at all:
  #
  #   ERROR: Use build.verbose instead of cmake.verbose for
  #   scikit-build-core >= 0.10
  #   ERROR Backend subprocess exited when trying to invoke
  #   get_requires_for_build_wheel
  #
  # This is the rename upstream itself made on main, applied to the release.
  # It is also the price of pinning the tag: main has this fix and the broken
  # module suffix, the tag has the working suffix and this.  One line here is
  # the cheaper half of that trade.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'cmake.verbose = true' 'build.verbose = true'
  '';

  build-system = [
    cython
    numpy
    scikit-build-core
    setuptools-scm
  ];

  # scikit-build-core drives CMake itself, from `[tool.scikit-build]` in
  # pyproject.toml.  cmake and ninja are here as programs for it to find; the
  # cmake setup hook must not run its own configure phase, which is what
  # dontUseCmakeConfigure turns off.  gfortran is not optional: the Siesta and
  # TranSiesta readers under src/sisl/io/siesta/ are Fortran, compiled into
  # `sisl.io.siesta._siesta`, and pyproject.toml disables them only on Windows
  # (`SKBUILD_CMAKE_ARGS = "-DWITH_FORTRAN=NO"` under cibuildwheel).
  nativeBuildInputs = [
    cmake
    ninja
    gfortran
  ];

  dontUseCmakeConfigure = true;

  # `[[tool.dynamic-metadata]] provider = scikit_build_core.metadata.setuptools_scm`
  # reads the version out of git, and fetchFromGitHub hands over a tree with no
  # .git.  Same treatment, and same reason for deriving it from `version`
  # instead of repeating the number, as ../sella/default.nix — including why the
  # `-unstable-` suffix has to come off: setuptools-scm hands the string to
  # `packaging`, which rejects anything that is not PEP 440.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" version);

  dependencies = [
    numpy
    pyparsing
    scipy
    xarray
  ];

  # The tests have to run against the *installed* package, and the way to do
  # that here is to run them from inside it.
  #
  # pyproject.toml sets `testpaths = ["src"]`, so by default pytest collects
  # src/sisl/**/tests/ — and collecting a file under src/ puts src/ on sys.path
  # ahead of site-packages, at which point `import sisl` finds the source tree,
  # which has all of the Python and none of the compiled extensions:
  #
  #   src/sisl/shape/_cylinder.py:12: in <module>
  #       from sisl._indices import indices_in_cylinder
  #   E   ModuleNotFoundError: No module named 'sisl._indices'
  #
  # `--pyargs sisl sisl_toolbox` was the first attempt and is worse: it collects
  # nothing at all for sisl, and sisl_toolbox has no `__init__.py`, so pytest
  # rejects it outright —
  #
  #   ERROR: module or package not found: sisl_toolbox (missing __init__.py?)
  #
  # Changing directory into site-packages sidesteps both.  The two arguments
  # are then plain paths rather than module names, so the namespace package is
  # not a special case; cwd is on sys.path, so the imports find the built
  # extensions beside them; and explicit arguments override `testpaths`.  The
  # wheel carries the tests — sisl/tests/, sisl/physics/tests/ and the rest sit
  # alongside `_indices.cpython-313-x86_64-linux-gnu.so`.
  preCheck = ''
    cd "$out/${python.sitePackages}"
  '';

  pytestFlags = [
    "sisl"
    "sisl_toolbox"
  ];

  # `slow` is upstream's own marker, declared in pyproject.toml.  A build is not
  # where a multi-hour numerical suite earns its keep, and the marked tests are
  # slow rather than differently-covered.
  #
  # disabledTestMarks, not `pytestFlags = [ "-m" "not slow" ]`: pytestFlags is
  # word-split on its way to pytest, which turns the expression into two
  # arguments and makes the second a path.  See the note in
  # ../fireworks/default.nix.
  disabledTestMarks = [ "slow" ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "sisl"
    "sisl.io"
    "sisl.io.siesta"
    "sisl.physics"
    "sisl_toolbox"
  ];

  meta = {
    description = "Toolbox for electronic structure calculations and tight-binding models";
    homepage = "https://github.com/zerothi/sisl";
    changelog = "https://zerothi.github.io/sisl/release.html";
    license = lib.licenses.mpl20;
    # Four console scripts, none named after the package.  sdata is the general
    # one — it dispatches on the file it is given — so it is what lib.getExe
    # should resolve to.
    mainProgram = "sdata";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
