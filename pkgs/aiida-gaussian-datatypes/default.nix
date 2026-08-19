{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  cp2k-input-tools,
  click,
  tabulate,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-gaussian-datatypes";
  version = "0.5.1";
  pyproject = true;

  # aiida-cp2k depends on this unbounded, so any recent release will do.
  #
  # Not fetchPypi: PyPI serves no sdist for 0.5.1 under either spelling, so
  # every mirror 404s — the same as ../cp2k-output-tools.  Note the owner is
  # dev-zero rather than aiidateam; this plugin has never lived under the
  # AiiDA organisation.
  src = fetchFromGitHub {
    owner = "dev-zero";
    repo = "aiida-gaussian-datatypes";
    tag = "v${version}";
    hash = "sha256-ZaifZ5hZNADTqt5Vfu/bQGjvT8NvPlX/cR2KBGCmn9E=";
  };

  build-system = [ setuptools ];

  pythonRelaxDeps = [ "aiida-core" ];

  # setup.json's install_requires is `aiida-core` and `cp2k-input-tools`.
  # cp2k-**input**-tools, not the output one this used to list: they are
  # unrelated projects by the same author, and the source imports only the
  # former — `from cp2k_input_tools.basissets import BasisSetData` in
  # basisset/data.py, and the matching pseudopotentials import.
  #
  # click and tabulate are undeclared upstream but genuinely imported, by the
  # CLI and the listing code respectively.
  dependencies = [
    aiida-core
    cp2k-input-tools
    click
    tabulate
  ];

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
  ];

  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [ "aiida_gaussian_datatypes" ];

  meta = {
    description = "AiiDA data plugin for Gaussian basis sets and pseudopotentials";
    homepage = "https://github.com/dev-zero/aiida-gaussian-datatypes";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
