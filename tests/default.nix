# tests/default.nix
#
# Dispatcher over the per-subject test suites.  It holds no tests of its own —
# each subdirectory owns everything about one package or module set:
#
#   qcarchive/default.nix   evaluation tests for the QCFractal NixOS modules
#   qcarchive/vm.nix        NixOS VM integration tests for the same
#   dotdrop/default.nix     integration tests for the dotdrop package
#
# Run everything that needs no VM:
#   nix-build tests -A all
#
# Run one suite, or one test within it:
#   nix-build tests -A qcarchive.all
#   nix-build tests -A qcarchive.server-defaults
#   nix-build tests -A dotdrop.roundtrip
#
# The VM tests are deliberately *not* reachable from `all` — they need KVM and
# take minutes.  Reach them through the flake (`nix build
# .#checks.<system>.vm-server-local-db`, or `just vm-test server-local-db`), or
# directly:
#   nix-build tests/qcarchive/vm.nix -A server-local-db

{
  pkgs ? import <nixpkgs> { },
}:

let
  # The suites disagree about what they need from pkgs, and each applies what
  # it needs itself: qcarchive/default.nix extends with overlays.qcfractal for
  # its overlay-contract tests and stubs the packages everywhere else, while
  # dotdrop/default.nix needs a real pkgs.dotdrop.  Passing a plain <nixpkgs>
  # through to both therefore works, and keeps `nix-build tests -A all` usable
  # without the caller knowing any of this.
  qcarchive = import ./qcarchive { inherit pkgs; };
  dotdrop = import ./dotdrop {
    pkgs = pkgs.extend (import ../overlays).dotdrop;
  };
in
{
  inherit qcarchive dotdrop;

  # Every non-VM test in the repo.
  all = pkgs.symlinkJoin {
    name = "nur-tests";
    paths = [
      qcarchive.all
      dotdrop.all
    ];
  };
}
