{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  pybind11,
  setuptools,

  # dependencies
  ase,
  numba,
  numpy,
  pandas,
  scipy,
  spglib,
  trainstation,

  # optional-dependencies
  highspy,

  # tests
  pytestCheckHook,
  pytest-xdist,
  xdoctest,

  # the C++ test runner's header library, a top-level attribute passed in by
  # ../../overlays/default.nix
  doctest,
}:

buildPythonPackage rec {
  pname = "icet";
  version = "4.0";
  pyproject = true;

  # Cluster expansions and Monte Carlo (the `mchammer` package, shipped in the
  # same distribution) for alloys.  Here first for ../atomate2's
  # `tests/common/jobs/test_transform.py::test_sqs`, which pymatgen's
  # `SQSTransformation(sqs_method="icet-enumeration")` runs through it.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/icet.
  src = fetchFromGitLab {
    owner = "materials-modeling";
    repo = "icet";
    tag = version;
    hash = "sha256-K0oOcTK3C0f/7OJDVMLpaIz6rR9aGEY/MHhfkSC5e8k=";
  };

  # setup.py builds the `_icet` extension from src/*.cpp against the Eigen
  # under src/3rdparty, so nixpkgs' eigen is not needed.
  build-system = [
    pybind11
    setuptools
  ];

  dependencies = [
    ase
    numba
    numpy
    pandas
    scipy
    spglib
    trainstation
  ];

  # highspy backs the linear-programming route to ground states in
  # `icet.tools.ground_state_finder`, imported behind a try.
  optional-dependencies = {
    optional = [ highspy ];
  };

  # Upstream's test job installs `.[test,optional]`, runs `xdoctest` over both
  # packages, then `pytest tests/`.  Of the `test` extra, coverage is its
  # reporting, flake8 is its separate style job, and nbmake is its notebook
  # job; that last one runs examples/ and is non-blocking upstream, because
  # Monte Carlo runs inside the notebooks set its run time.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    xdoctest
  ]
  ++ optional-dependencies.optional;

  enabledTestPaths = [ "tests" ];

  # The rest of upstream's test stage.  Like the pytest run, the doctests take
  # icet's Python half from the source tree, which is what is installed, and
  # `_icet` from the build.  The C++ suite is its own CI job, compiled from the
  # library sources rather than the extension, which is why PyBinding.cpp is
  # left out exactly as upstream leaves it out.  Upstream's `-Werror` is not
  # carried: it pins the warnings of whatever g++ its image has, and a newer
  # compiler's new warning is not a defect in icet.
  postCheck = ''
    python -m xdoctest icet
    python -m xdoctest mchammer

    mkdir -p tests/cpp/build
    $CXX -std=c++17 -Wall -Wextra -Isrc -Isrc/3rdparty/eigen3 \
      -I${doctest}/include \
      -o tests/cpp/build/test_cpp tests/cpp/test_main.cpp \
      $(ls src/*.cpp | grep -v '^src/PyBinding\.cpp$') \
      -lpthread
    ./tests/cpp/build/test_cpp
  '';

  pythonImportsCheck = [
    "icet"
    "mchammer"
    "_icet"
  ];

  meta = {
    description = "Pythonic approach to cluster expansions";
    homepage = "https://icet.materialsmodeling.org";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
