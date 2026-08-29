{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

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
  version = "0.16.4-unstable-2026-08-25";
  pyproject = true;

  # `fetchSubmodules` is deliberately left at its default of false.  The one
  # submodule, `files`, is zerothi/sisl-files — a separate repository of
  # reference output from Siesta, TranSiesta and friends, used only by tests
  # that ask for the `sisl_files` fixture.  src/sisl/conftest.py xfails exactly
  # those when SISL_FILES_TESTS is unset, which is the state here, so fetching
  # it would add a large download and change nothing that runs.
  src = fetchFromGitHub {
    owner = "zerothi";
    repo = "sisl";
    rev = "bbbb64a97c6fd813beba56272749cdc8ffda8942";
    hash = "sha256-8G0cEj65371Y2MQesc1z1aw/EbujCtj+xvZM/Tr1Mas=";
  };

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
