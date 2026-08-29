{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,

  # build-system
  cmake,
  ninja,
  setuptools,

  # The C++ library, from ../chemfiles.  Threaded in explicitly at the
  # callPackage site in ../../overlays/default.nix rather than taken from the
  # ambient scope, because *this* package's own attribute is also called
  # `chemfiles` — a python-set callPackage resolves the Python attribute first,
  # so a bare `chemfiles` argument would bind to this derivation itself.  The
  # same trick ../../overlays/default.nix already uses for aiida-core's `jq`.
  chemfilesLib,

  # dependencies
  numpy,
}:

buildPythonPackage rec {
  pname = "chemfiles";
  # 0.11.0-rc1 rather than the 0.10.4 tag this commit is described by: the tag
  # is a year old and `src/chemfiles/__init__.py`, which setup.py greps for the
  # version, already says 0.11.0-rc1 here.  Taking the tag would install a
  # distribution whose recorded version disagrees with its own source.
  version = "0.11.0-rc1-unstable-2025-10-16";
  pyproject = true;

  # fetchSubmodules is deliberately absent.  The repository carries the whole
  # C++ library as a submodule at lib/, and CMakeLists.txt falls back to
  # building it whenever `find_package(chemfiles)` misses — which would compile
  # and ship a second, private copy of a library we already package.
  #
  # Leaving the submodule out is what makes that fallback *loud*: with no
  # lib/CMakeLists.txt the fallback branch hits a FATAL_ERROR instead of
  # quietly succeeding.  That matters more than it looks, because the runtime
  # half of the miss is silent — src/chemfiles/_c_lib.py does
  #
  #     try:     from .external import EXTERNAL_CHEMFILES
  #     except ImportError:  EXTERNAL_CHEMFILES = False
  #
  # and then looks for a libchemfiles.so sitting next to itself.  A build that
  # missed the external library would produce an importable package that only
  # fails when someone opens a trajectory.
  src = fetchFromGitHub {
    owner = "chemfiles";
    repo = "chemfiles.py";
    rev = "8172c78d2c1f64793acc45ec655a6ae4a19e0861";
    hash = "sha256-2MsTAg2zsNlY32GtTMrt4EJdPG/gDLSewd7D7/Q1Sjs=";
  };

  # Upstream asks for the wrong version of its own library, and the request is
  # an exact-minor gate rather than a floor.  CMakeLists.txt:10 has
  #
  #     find_package(chemfiles CONFIG QUIET 0.10)
  #
  # while ../chemfiles writes its package version file with
  # `COMPATIBILITY SameMinorVersion`, which means "0.10" is satisfied only by a
  # 0.10.x — not by the 0.11.0-rc1 that this very commit pins as its `lib`
  # submodule (a2319946, the 0.11.0-rc1 tag).  So the external-library branch
  # can never be taken, and the build falls through to:
  #
  #   CMake Error at CMakeLists.txt:59 (message):
  #     The git submodule for chemfiles is not initalized.
  #
  # Upstream does not notice because their wheels vendor the submodule; the
  # external path is for distributors, and we are the ones exercising it.
  #
  # Bumping the request rather than downgrading the library: the submodule pin
  # is upstream's own statement of which chemfiles this binding is written
  # against, and src/chemfiles/__init__.py agrees, calling itself 0.11.0-rc1.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'find_package(chemfiles CONFIG QUIET 0.10)' \
                     'find_package(chemfiles CONFIG QUIET 0.11)'
  '';

  build-system = [
    cmake
    ninja
    setuptools
  ];

  # setup.py drives cmake itself, from its build_py and build_ext commands, so
  # nixpkgs' cmake setup hook must not also try to configure the tree.  The
  # hook's environment half still runs, and that is the part that matters: it
  # exports NIXPKGS_CMAKE_PREFIX_PATH — not CMAKE_PREFIX_PATH — which nixpkgs'
  # cmake reads through its own nixpkgs-cmake-prefix-path.patch.  setup.py
  # builds the cmake command line itself and passes no prefix, so that
  # environment variable is the only route by which chemfilesLib is findable.
  dontUseCmakeConfigure = true;

  buildInputs = [ chemfilesLib ];

  dependencies = [ numpy ];

  # Assert the external library was actually found.  cmake writes external.py
  # only on the `find_package` hit, so its presence — and the store path inside
  # it — is the difference between binding our chemfiles and shipping a private
  # copy.  Checked here rather than trusted because both failure modes above
  # produce a package that imports.
  postInstall = ''
    externalPy="$out/${python.sitePackages}/chemfiles/external.py"
    if [ ! -f "$externalPy" ]; then
      echo "chemfiles-python: external.py is missing, so cmake did not find" >&2
      echo "the chemfiles C++ library and would have used a vendored copy." >&2
      exit 1
    fi
    grep -q '${chemfilesLib}' "$externalPy" || {
      echo "chemfiles-python: external.py does not point at ${chemfilesLib}:" >&2
      cat "$externalPy" >&2
      exit 1
    }
  '';

  # pytestCheckHook is not used, and this is the sdist-has-no-tests trap wearing
  # a new hat.  The suite is real — twelve modules under tests/ — but they are
  # named atom.py, cell.py, frame.py and so on, matching neither `test_*.py` nor
  # `*_test.py`, so pytest's default collection finds *nothing* and the check
  # phase passes having run zero assertions.
  #
  # Upstream's tox runs `unittest discover -s tests -p "*.py"`, which is
  # reproduced here.  `-s tests` also puts that directory on sys.path, which the
  # modules rely on: they `import _utils` by bare name.
  checkPhase = ''
    runHook preCheck

    ${python.interpreter} -m unittest discover -s tests -p "*.py" --verbose

    runHook postCheck
  '';

  pythonImportsCheck = [ "chemfiles" ];

  meta = {
    description = "Python binding for the chemfiles trajectory reading and writing library";
    homepage = "https://chemfiles.org/chemfiles.py";
    changelog = "https://github.com/chemfiles/chemfiles.py/blob/master/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
