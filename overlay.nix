# You can use this file as a nixpkgs overlay. This is useful in the
# case where you don't want to add the whole NUR namespace to your
# configuration.

_self: super:
let
  # Keep in sync with the same predicate in ./ci.nix.
  #
  # python313Packages is ours rather than part of the NUR template's list, and
  # is the one that would do real damage if it leaked: it would replace the
  # consumer's python313Packages with the one ./default.nix builds from its own
  # pkgs'.  See the comment at that attribute.
  isReserved =
    n:
    n == "lib"
    || n == "overlays"
    || n == "nixosModules"
    || n == "homeModules"
    || n == "darwinModules"
    || n == "flakeModules"
    || n == "python313Packages";
  nameValuePair = n: v: {
    name = n;
    value = v;
  };
  nurAttrs = import ./default.nix { pkgs = super; };

in
builtins.listToAttrs (
  map (n: nameValuePair n nurAttrs.${n}) (
    builtins.filter (n: !isReserved n) (builtins.attrNames nurAttrs)
  )
)
