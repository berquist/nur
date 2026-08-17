{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  argcomplete,
  jsonschema,
  regex,
  unidecode,

  # tests
  pytestCheckHook,
  numpy,
}:

buildPythonPackage rec {
  pname = "basis-set-exchange";
  version = "0.12-unstable-2026-08-07";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MolSSI-BSE";
    repo = "basis_set_exchange";
    rev = "4adaf1372c7101620ca1a9f3130be9ae97fb8f30";
    hash = "sha256-KShYrcrN9QpC8DDJvSCKOZFwV+QpcnjNBAGPVb4Zcdk=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # setuptools-scm reads the version out of git, and fetchFromGitHub hands over
  # a tree with no .git.  Without this the build fails outright rather than
  # falling back, because upstream declares `dynamic = ["version"]` with no
  # fallback configured.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  dependencies = [
    argcomplete
    jsonschema
    regex
    unidecode
  ];

  nativeCheckInputs = [
    pytestCheckHook
    numpy
  ];

  # The `tests` extra also lists `wignernj`, which is not in nixpkgs.  It is
  # used only by the spherical-harmonic transformation tests, which skip
  # themselves when the import fails.
  #
  # basis_set_exchange/tests/test_curate.py drives the `bsecurate` CLI against
  # the authoritative source data and is slow rather than fragile; it stays in.
  pythonImportsCheck = [
    "basis_set_exchange"
    "basis_set_exchange.misc"
    "basis_set_exchange.writers"
  ];

  meta = {
    description = "Basis Set Exchange — a library and CLI for quantum chemistry basis sets";
    homepage = "https://github.com/MolSSI-BSE/basis_set_exchange";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
