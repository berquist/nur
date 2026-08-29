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
  trexio,

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

    # Upstream's `trexio` extra.  This resolves to ../trexio, the Python
    # binding, *not* to nixpkgs' top-level `trexio` — that attribute is the C
    # library, which installs nothing importable.  The two share a name and
    # differ entirely in what they are, so the distinction is worth stating
    # here: see ../../overlays/default.nix, where the binding is deliberately
    # left out of the top level to keep from shadowing the library.
    #
    # Six test modules guard themselves with `pytest.importorskip("trexio")`,
    # so before this they skipped rather than failed — 8 skips in the last
    # green run, which is the number to watch go down.
    trexio
  ];

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
