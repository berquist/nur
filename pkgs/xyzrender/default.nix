{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  wheel,

  # dependencies
  cairosvg,
  graphrc,
  ipykernel,
  numpy,
  pillow,
  resvg-py,
  xyzgraph,

  # cclib is not in nixpkgs and arrives from a flake input, which
  # ../../overlays/default.nix cannot reach.  Defaulted rather than required so
  # that evaluation still succeeds on the bare NUR path, with meta.broken below
  # keeping `just ci-build` from attempting it.  See ../harmonwig/default.nix
  # for the full explanation.
  cclib ? null,

  # tests
  ase,
  pytestCheckHook,
  rdkit,
}:

buildPythonPackage {
  pname = "xyzrender";
  # 0.3.9, not the v0.3.1 that `git describe` reports 17 commits back.
  version = "0.3.9-unstable-2026-08-13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aligfellow";
    repo = "xyzrender";
    rev = "69a219f6474eae20886726c2270806e27de98e77";
    hash = "sha256-NHGdbMSxiOujICU8t7M0RvTLUO1qn9zMDV6Lca2SOGk=";
  };

  build-system = [
    setuptools
    wheel
  ];

  # `ipykernel>=7.2.0` against nixpkgs' 7.1.0.  A runtime dependency in
  # [project.dependencies], so pythonRelaxDeps reaches it — the distinction
  # ../sella documents, where the same hook could not touch a [build-system]
  # requirement.
  #
  # Worth noting that ipykernel is a *core* dependency here rather than an
  # extra, which is unusual for a rendering library: xyzrender offers inline
  # display in notebooks and does not gate it.
  pythonRelaxDeps = [ "ipykernel" ];

  dependencies = [
    cairosvg
    cclib
    graphrc
    ipykernel
    numpy
    pillow
    resvg-py
    xyzgraph
  ];

  # ase and rdkit are optional extras (`cif` and `smi`) that upstream's dev
  # group installs anyway, because test_formats.py needs them for its pdb and
  # mol/sdf fixtures.  Supplied rather than skipped, per the same reasoning as
  # ../fireworks' igraph.
  #
  # The other two extras stay out and cost nothing.  `vmol` is not in nixpkgs,
  # and test_viewer.py never wants the real thing — it monkeypatches sys.modules
  # with a fake, and its first test asserts the *absence* path raises
  # "Interactive viewer requires vmol".  `shelxfile` is likewise missing, and
  # test_formats.py guards its SHELXL tests with
  # `importlib.util.find_spec("shelxfile") is None`, so they skip cleanly.
  nativeCheckInputs = [
    ase
    pytestCheckHook
    rdkit
  ];

  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  pythonImportsCheck = [
    "xyzrender"
    "xyzrender.cli"
  ];

  meta = {
    description = "Publication-quality molecular graphics";
    homepage = "https://github.com/aligfellow/xyzrender";
    license = lib.licenses.mit;
    mainProgram = "xyzrender";
    maintainers = with lib.maintainers; [ berquist ];
    broken = cclib == null;
  };
}
