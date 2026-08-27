{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "mda-xdrlib";
  version = "0.2.0.dev20251012";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MDAnalysis";
    repo = "mda-xdrlib";
    rev = "5bc9bbc74a32361d15fcb59ad45f45007cb856cb";
    hash = "sha256-4Hsy61ZOifNguSNZKlFcJ7LgL7AnaQKUpGMcqjFYGds=";
  };

  # versioningit derives the version from git, and fetchFromGitHub hands over a
  # tree with no .git in it — so the build falls back to `default-version`,
  # which upstream sets to the placeholder "1+unknown".  Rewriting the fallback
  # is the whole fix; there is nothing else in the file to disturb.  The same
  # applies to ../griddataformats and ../qmzyme.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'default-version = "1+unknown"' 'default-version = "${version}"'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "mda_xdrlib" ];

  meta = {
    description = "Stand-alone xdrlib module, extracted from CPython 3.10.8";
    homepage = "https://github.com/MDAnalysis/mda-xdrlib";
    license = lib.licenses.psfl;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
