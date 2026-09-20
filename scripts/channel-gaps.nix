# scripts/channel-gaps.nix
#
# The two halves of scripts/channel-gaps.sh's work, in one file so that the
# attribute set being probed is described exactly once.  Called with no `attr`
# it lists what to probe; called with one it forces that attribute and nothing
# else.  See the script's header for why each attribute needs its own process.
#
# `<nixpkgs>` rather than an argument: the script points NIX_PATH at the channel
# before calling, which is what `just ci CHANNEL` does too.
{
  attr ? null,
}:
let
  pkgs = import <nixpkgs> { };
  inherit (pkgs) lib;
  root = import ../. { inherit pkgs; };

  # ---------------------------------------------------------------------------
  # What to probe
  # ---------------------------------------------------------------------------
  #
  # Listing is deliberately cheap and total: `builtins.attrNames` does not force
  # a value, so this half evaluates even on a channel where forcing one of them
  # would abort — which is the whole situation the script exists for.
  #
  # Three sources, because no one of them covers the others:
  #
  #   * every top-level attribute of ../default.nix, minus the reserved keys,
  #     which are module sets and package sets rather than derivations;
  #   * `internalPackages` as a single target, because its `filterAttrs` forces
  #     every member while the attrset is being built, so an abort there lands
  #     on the attribute itself rather than on anything under it;
  #   * `python3Packages.<name>` for every directory under ../pkgs the set
  #     actually has.  Most of this repository is reachable no other way —
  #     about sixty packages are internal dependencies with no top-level alias,
  #     and `deepmd-kit`, which cost a CI round, is one of them.
  #
  # Intersecting the third list with `attrNames` is what keeps it honest.  A
  # directory name is not always the attribute — ../pkgs/chemfiles-python is
  # `python3Packages.chemfiles` — and probing a name the set does not have
  # would report a gap that is really a spelling.

  # The same list ../overlay.nix and ../ci.nix filter on, for the same reason:
  # these are not derivations, and forcing one proves nothing.
  reserved = [
    "lib"
    "overlays"
    "nixosModules"
    "homeModules"
    "darwinModules"
    "flakeModules"
    "python3Packages"
    "internalPackages"
  ];

  ourDirectories = builtins.attrNames (
    lib.filterAttrs (_: entryType: entryType == "directory") (builtins.readDir ../pkgs)
  );

  targets =
    lib.subtractLists reserved (builtins.attrNames root)
    ++ [ "internalPackages" ]
    ++ map (name: "python3Packages.${name}") (
      builtins.filter (name: root.python3Packages ? ${name}) ourDirectories
    );

  # ---------------------------------------------------------------------------
  # How to force one
  # ---------------------------------------------------------------------------
  #
  # `drvPath` and `meta`, which is what `just ci-eval` forces through
  # `nix-env -qa --meta --drv-path` and so the same bar.
  #
  # Broken and unfree packages get `meta` alone.  Forcing either one's `drvPath`
  # is an evaluation error rather than a skip, and reporting that as a channel
  # gap would be exactly backwards: `meta.broken` is this repository saying it
  # already knows.  ../ci.nix filters on both properties for the same reason,
  # and its note is the long version.  The seven cclib dependants are broken on
  # every channel by design, ../pkgs/phono3py is broken wherever phonopy is
  # older than 4.4, and ../pkgs/tensorpotential is the unfree one.
  #
  # `meta.broken` is still *forced*, so a `broken` expression that throws — one
  # reading a version off a package the channel lacks, say — is still caught.
  #
  # A null is a package the overlay deliberately gated off on this channel
  # (`fairchem-core`, `sevenn`, …), so it forces to itself and passes.  An
  # attrset that is not a derivation is forced only as far as its names, since
  # its members are probed in their own right.
  force =
    value:
    if value == null then
      true
    else if lib.isDerivation value then
      if (value.meta.broken or false) || (value.meta.unfree or false) then
        true
      else
        builtins.seq value.drvPath true
    else if builtins.isAttrs value then
      builtins.deepSeq (builtins.attrNames value) true
    else
      builtins.seq value true;
in
if attr == null then
  lib.concatStringsSep "\n" (lib.naturalSort targets)
else
  force (lib.getAttrFromPath (lib.splitString "." attr) root)
