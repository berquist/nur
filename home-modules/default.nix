# home-modules/default.nix
#
# As with nixos-modules, an attrset of *paths*, not functions.  Paths avoid
# double-import conflicts when the same module is pulled in from more than one
# place in the module system.
{
  hydrus-client = ./hydrus-client.nix;
}
