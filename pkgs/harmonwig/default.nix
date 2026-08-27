{
  lib,
  buildPythonApplication,
  fetchFromGitHub,

  # build-system
  uv-build,

  # dependencies
  ase,
  tqdm,

  # cclib is not in nixpkgs, and upstream ships its own flake — so it arrives
  # from a flake input, which ../../overlays/default.nix cannot reach: that file
  # is imported without flakes by ../../default.nix, ../../overlay.nix and
  # ../../ci.nix.  The same constraint the header of ../../tests/qcarchive/vm.nix
  # documents for Psi4.
  #
  # Defaulted rather than required so that evaluation still succeeds on the bare
  # NUR path — `nix-env -f . -qa '*'`, which `just ci-eval` runs, forces every
  # attribute — and meta.broken below is what keeps `just ci-build` from trying
  # to build something it cannot.  Through the flake, cclib is present and this
  # is a normal package.
  cclib ? null,

  # tests
  pytestCheckHook,
  numpy,
}:

buildPythonApplication rec {
  pname = "harmonwig";
  version = "0.1.0a0-unstable-2026-08-16";
  pyproject = true;

  # Never released to PyPI; upstream's own install instructions are
  # `uv tool install "harmonwig @ git+https://github.com/ispg-group/harmonwig.git"`.
  src = fetchFromGitHub {
    owner = "ispg-group";
    repo = "harmonwig";
    rev = "5ae0c0c90c89a99f329c77c9953dc0e20c72a08f";
    hash = "sha256-tSFj/1ZLgZWEmbM3JbPIm3RX/AZ77+Oxw1JsIedc0Q8=";
  };

  build-system = [ uv-build ];

  # harmonwig asks for `cclib~=1.8.0`, which is `>=1.8.0, ==1.8.*` and therefore
  # excludes the 1.9 the cclib flake builds.  The bound is upstream pinning the
  # release that was current, not a real incompatibility: only cclib.io.ccread
  # is used, and its signature is unchanged.
  pythonRelaxDeps = [ "cclib" ];

  dependencies = [
    ase
    tqdm
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [
    pytestCheckHook
    numpy
  ];

  pythonImportsCheck = [
    "harmonwig"
    "harmonwig.harmonwig"
  ];

  meta = {
    description = "Harmonic Wigner sampling of vibrational wavefunctions from QM calculations";
    homepage = "https://github.com/ispg-group/harmonwig";
    license = lib.licenses.mit;
    mainProgram = "harmonwig";
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through the flake; see the cclib argument above.
    broken = cclib == null;
  };
}
