{
  lib,
  buildPythonApplication,
  fetchFromGitHub,

  # build-system
  hatchling,
  hatch-vcs,

  # dependencies
  numpy,
  scikit-image,
  textual,

  # tests
  pytestCheckHook,
  pytest-asyncio,
}:

buildPythonApplication rec {
  pname = "moltui";
  version = "0.6.1.dev0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "kszenes";
    repo = "moltui";
    tag = "v${version}";
    hash = "sha256-r22zuHjqKb0gVL5u1trtcCc32qO0zq4l2HlPNsJockc=";
  };

  build-system = [
    hatchling
    hatch-vcs
  ];

  dependencies = [
    numpy
    scikit-image
    textual
  ];

  # The `trexio` extra is deliberately not enabled.  nixpkgs carries the
  # *C library* as a top-level `trexio` (pkgs/by-name/tr/trexio) but no Python
  # module — the derivation lists python3 and swig as native build inputs, for
  # code generation, and installs nothing importable.  The extra wants the PyPI
  # distribution, which is the swig wrapper over that same library.
  #
  # Nothing is silently lost by leaving it out: the six modules that exercise
  # trexio all guard themselves with `pytest.importorskip("trexio")`, so they
  # skip rather than fail.  Once the binding is packaged, adding it here is the
  # whole change.

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
  ];

  pythonImportsCheck = [
    "moltui"
    "moltui.app"
  ];

  meta = {
    description = "Terminal user interface for viewing molecular structures, orbitals and normal modes";
    homepage = "https://github.com/kszenes/moltui";
    changelog = "https://github.com/kszenes/moltui/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "moltui";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
