# default.nix
#
# NUR entry point. Applies our overlays to a local pkgs' so that:
#   nix-build -A qcportal              works
#   nix-build -A qcfractal             works
#   python3.withPackages (p: [...])    works (same store paths, no duplication)
#
# overlay.nix (the NUR template file) derives itself from this file by
# filtering reserved names, so it continues to work unchanged.

{
  pkgs ? import <nixpkgs> { },
}:

let
  overlays = import ./overlays;

  # Compose all overlays in overlays/ into one and apply it.
  pkgs' = pkgs.extend (pkgs.lib.composeManyExtensions (builtins.attrValues overlays));

  py = pkgs'.python3Packages;
in
{
  # Reserved keys — not lifted into the nixpkgs overlay by overlay.nix.
  lib = import ./lib { pkgs = pkgs'; };
  nixosModules = import ./nixos-modules;
  overlays = overlays;

  # Non-Python packages.
  example-package = pkgs'.callPackage ./pkgs/example-package { };

  # Python packages, reached through the extended python3Packages so that
  # these derivations are identical to what python3.withPackages returns.
  inherit (py)
    parsl
    qcportal
    qcfractal
    qcfractalcompute
    qcarchivetesting
    ;
}
