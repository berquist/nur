{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  wheel,

  # dependencies
  networkx,
  numpy,
  xyzgraph,

  # cclib is not in nixpkgs and arrives from a flake input, which
  # ../../overlays/default.nix cannot reach.  Defaulted rather than required so
  # that evaluation still succeeds on the bare NUR path, with meta.broken below
  # keeping `just ci-build` from attempting it.  See ../harmonwig/default.nix
  # for the full explanation.
  cclib ? null,

  # tests
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "graphrc";
  # 1.3.7, not the v1.3.5 that `git describe` reports 41 commits back.  Note
  # also that the *distribution* is `graphRC` while the import name and this
  # attribute are `graphrc`; ../xyzrender depends on it under the former.
  version = "1.3.7-unstable-2026-07-12";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aligfellow";
    repo = "graphRC";
    rev = "69f7289aa36ed11ed269e405f2440f3b7a74e924";
    hash = "sha256-H3sebFHS4EuIpexhmBet8Seuoq5wHTy/PANWujrI2Zo=";
  };

  build-system = [
    setuptools
    wheel
  ];

  dependencies = [
    cclib
    networkx
    numpy
    xyzgraph
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "graphrc"
    "graphrc.cli"
  ];

  meta = {
    description = "Internal coordinate analysis of vibrational modes";
    homepage = "https://github.com/aligfellow/graphRC";
    license = lib.licenses.mit;
    mainProgram = "graphrc";
    maintainers = with lib.maintainers; [ berquist ];
    broken = cclib == null;
  };
}
