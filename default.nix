# default.nix
#
# NUR entry point. Applies our overlays to a local pkgs' so that:
#   nix-build -A qcportal                works
#   nix-build -A qcfractal               works
#   python313.withPackages (p: [...])    works (same store paths, no duplication)
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

  # Pinned rather than python3Packages: nixpkgs-unstable has moved python3 to
  # 3.14, where qcportal cannot even be imported (see pkgs/qcportal/default.nix
  # for the qcelemental mechanism).  Following the default interpreter would
  # mean this repo ships nothing at all on unstable, and would take every VM
  # test in `nix flake check` down with it the moment flake.lock is bumped past
  # the switch.  Revert to python3Packages once upstream releases its pydantic
  # v2 migration.
  #
  # Keep in sync with the top-level aliases in overlays/default.nix; the
  # overlay-python-pin eval test asserts the two agree.
  py = pkgs'.python313Packages;
in
{
  # Reserved keys — not lifted into the nixpkgs overlay by overlay.nix.
  nixosModules = import ./nixos-modules;
  inherit overlays;

  # Python *applications*: reached through the overlay rather than
  # callPackage'd here, so that pkgs.dotdrop and this attribute are the same
  # derivation.  Built against the default python3, not the 3.13 pin below.
  #
  # harmonwig is here too, but on the bare NUR path it carries meta.broken:
  # its cclib comes from a flake input that ./overlays cannot reach.  See
  # pkgs/harmonwig/default.nix, and flake.nix for the working instantiation.
  inherit (pkgs') dotdrop harmonwig;

  # Python packages, reached through the extended python313Packages so that
  # these derivations are identical to what python313.withPackages returns.
  inherit (py)
    parsl
    qcportal
    qcfractal
    qcfractalcompute
    qcarchivetesting

    aiida-core
    aiida-cp2k
    aiida-octopus
    aiida-orca
    aiida-psi4
    aiida-quantumespresso
    ;
}
