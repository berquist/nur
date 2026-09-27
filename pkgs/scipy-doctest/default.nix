{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  numpy,
  pytest,

  # tests
  pytestCheckHook,
  matplotlib,
  scipy,
}:

buildPythonPackage rec {
  pname = "scipy-doctest";
  version = "2.2.0";
  pyproject = true;

  # A pytest plugin for doctests with numerical output.  Here for
  # ../array-api-extra's doctest run, which configures it from docs/conftest.py.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in
  # wc/scipy_doctest.
  src = fetchFromGitHub {
    owner = "scipy";
    repo = "scipy_doctest";
    tag = "v${version}";
    hash = "sha256-DOpu0dvCoCx6JSTDvNA/dwLbGKZ4BLpv3GGaTH2XJjs=";
  };

  build-system = [ flit-core ];

  dependencies = [
    numpy
    pytest
  ];

  # Upstream's `test` extra.  Several of the doctest case files under
  # scipy_doctest/tests draw with matplotlib.
  nativeCheckInputs = [
    pytestCheckHook
    matplotlib
    scipy
  ];

  # matplotlib creates ~/.config/matplotlib on import, and /homeless-shelter is
  # not writable.  preBuild rather than preCheck so that pythonImportsCheck is
  # covered too; see ../aiida-core/default.nix.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export MPLCONFIGDIR="$HOME/.config/matplotlib"
    mkdir -p "$MPLCONFIGDIR"
  '';

  # The suite ships inside the package rather than beside it.
  enabledTestPaths = [ "scipy_doctest/tests" ];

  pythonImportsCheck = [
    "scipy_doctest"
    "scipy_doctest.plugin"
  ];

  meta = {
    description = "Doctest plugin for numerical Python code, with floating-point aware output checking";
    homepage = "https://github.com/scipy/scipy_doctest";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
