{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  numpy,
  setuptools,
  wheel,

  # native libraries, passed from the top level in ../../overlays/default.nix:
  # inside a Python package set `spglib` is the Python module, and this links
  # the C library, so it goes by the name of what it links.
  boost,
  eigen,
  lapack,
  libsymspg,

  # dependencies
  ase,
  spglib,
}:

buildPythonPackage {
  pname = "alm";
  version = "1.4.0-unstable-2024-06-02";
  pyproject = true;

  # ALM, the force-constant fitter from ALAMODE, as its Python binding: what
  # ../atomate2's `alamode` extra installs, and what both its hiphive and its
  # pheasy flows call to count the free parameters of the harmonic force
  # constants.  The `try: from alm import ALM` in those modules only defers the
  # failure to the call.
  #
  # `develop` rather than a tag, because that is what atomate2 names
  # (`ALM.git@develop#subdirectory=python`) and because the tags, `v.0.9.x`,
  # predate the binding's `1.4.0` by 587 commits.  Hash from
  # ../../scripts/offline-src-hash.sh against a clone in wc/ALM.
  src = fetchFromGitHub {
    owner = "ttadano";
    repo = "ALM";
    rev = "f1d668fdee66e7e7218a04c88daf19d0e14fce0c";
    hash = "sha256-DKhDH0zQ0xJxhA1tC9AWt6r9YHzn7lCThtpPI2eIiv0=";
  };

  # python/setup.py compiles the C++ in ../src into the extension itself
  # (`compile_with_sources = True`), so the whole tree is unpacked and only the
  # build starts one directory down.
  sourceRoot = "source/python";

  # `alm = "alm:main"` names a function the package does not define, so the
  # console script it would install fails on every invocation.  Upstream's
  # binding is a library; the `alm` program is the C++ one, which this does not
  # build.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '[project.scripts]
    alm = "alm:main"
    ' ""
  '';

  build-system = [
    numpy
    setuptools
    wheel
  ];

  # setup.py links `-lsymspg -llapack -lgomp` and looks for headers under
  # `$CONDA_PREFIX/include` and `$CONDA_PREFIX/include/eigen3`.  Boost and
  # spglib are found through their buildInputs' include paths; Eigen installs
  # under include/eigen3, which nothing puts on the path, so CONDA_PREFIX points
  # at it rather than setup.py being patched to say the same thing.
  buildInputs = [
    boost
    eigen
    lapack
    libsymspg
  ];

  env.CONDA_PREFIX = "${eigen}";

  # numpy for the extension, spglib and ase for alm/fcsxml.py, the FCSXML
  # writer, which imports both at module scope.
  dependencies = [
    ase
    numpy
    spglib
  ];

  # test/ holds two fitting scripts and their data rather than a suite: they
  # print RMS force constants and assert nothing.  Running them still proves
  # the part that can go wrong here — that the extension links and fits.
  checkPhase = ''
    runHook preCheck
    pushd ../test
    python Si_fitting.py
    python SiC_fitting.py
    popd
    runHook postCheck
  '';

  pythonImportsCheck = [
    "alm"
    "alm.fcsxml"
  ];

  meta = {
    description = "Force constant fitter from ALAMODE, as a Python extension";
    homepage = "https://github.com/ttadano/ALM";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
