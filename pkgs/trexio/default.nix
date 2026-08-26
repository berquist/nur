{
  lib,
  buildPythonPackage,
  fetchPypi,
  fetchFromGitHub,

  # build-system
  numpy,
  pkgconfig,
  setuptools,
  wheel,

  # native
  pkg-config,

  # the HDF5 back end
  hdf5,

  # tests
  pytestCheckHook,
}:

let
  version = "2.6.1";

  # The sdist-has-no-tests trap, in its most pointed form yet: python/MANIFEST.in
  # includes `test/benzene_data.py` and `test/conftest.py` and stops there, so
  # the sdist ships the suite's *fixtures and helpers* but not the suite itself.
  # pytest would collect zero items and pass.
  #
  # test_api.py is a thousand-odd lines covering every back end, so it is worth
  # going back to the tag for.  Only that one file is used; everything else
  # comes from the sdist, so the generated sources stay the ones upstream
  # published.
  #
  # A `let` binding rather than a derivation attribute: interpolating it into
  # preCheck is already what makes it a build input, and as an attribute it
  # would also become an environment variable in the builder for no reason.
  testSrc = fetchFromGitHub {
    owner = "TREX-CoE";
    repo = "trexio";
    rev = "v${version}";
    # The same hash nixpkgs' pkgs/by-name/tr/trexio/package.nix records for this
    # tag, so this shares its fetch rather than adding one.
    hash = "sha256-iESt7dXta/Enpgb418js26y5+YvROsqgxvNhgAgXd/I=";
  };
in

buildPythonPackage {
  pname = "trexio";
  inherit version;
  pyproject = true;

  # From PyPI rather than from the git tag, which is the unusual choice here and
  # the deliberate one.
  #
  # TREXIO's C sources are *generated*: src/trexio.c and friends are tangled out
  # of org-mode files, and python/src/pytrexio_wrap.c is produced by SWIG from
  # pytrexio.i.  The git checkout carries neither — which is why nixpkgs'
  # own `pkgs.trexio` lists emacs and swig as nativeBuildInputs.  Building the
  # Python API from the tag would mean reproducing that whole generation step
  # just to get to setup.py.
  #
  # The sdist is the output of `make python-sdist`, and ships all of it
  # pre-generated.  setup.py is written for exactly this case; it even carries a
  # branch commented "explicit hack needed when building from sdist tarball".
  #
  # The hash is not guesswork: it is the sha256 recorded for this exact file in
  # ../../wc/moltui/uv.lock, converted with `nix hash convert`.
  src = fetchPypi {
    pname = "trexio";
    inherit version;
    hash = "sha256-Li4dN/scLzcc+jLQdDTR1wPnUA6vdZCwH+m6UWmClEc=";
  };

  build-system = [
    numpy
    pkgconfig
    setuptools
    wheel
  ];

  # `pkgconfig` above is the Python module setup.py imports to locate HDF5;
  # `pkg-config` here is the program that module shells out to.  Both are
  # needed and they are not the same thing — without the program, setup.py's
  # `pk.exists('hdf5')` returns false and the extension is quietly built with
  # the TEXT back end only, printing
  #
  #   pkg-config could not locate HDF5; installing TREXIO with TEXT back-end
  #   only!
  #
  # and carrying on to a successful build that cannot open an HDF5 file.
  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ hdf5 ];

  dependencies = [ numpy ];

  nativeCheckInputs = [ pytestCheckHook ];

  # See the note above testSrc for why the suite is restored from the tag.  The
  # enabledTestPaths glob below aborts if this copy ever stops landing, which is
  # the guard that keeps the whole thing from silently reverting to zero tests.
  preCheck = ''
    cp ${testSrc}/python/test/test_api.py test/
  '';

  enabledTestPaths = [ "test/test_api.py" ];

  pythonImportsCheck = [
    "trexio"
    # The SWIG extension, imported explicitly: the pure-Python trexio.py wrapper
    # imports fine on its own even when the extension failed to build.
    "pytrexio"
  ];

  meta = {
    description = "File format and library for the storage of quantum chemical wave functions";
    homepage = "https://trex-coe.github.io/trexio/";
    changelog = "https://github.com/TREX-CoE/trexio/releases/tag/v${version}";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
