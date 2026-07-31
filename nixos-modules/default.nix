# nixos-modules/default.nix
#
# NUR requires nixosModules to be an attrset of *paths*, not functions.
# Paths avoid double-import conflicts when the same module is pulled in
# from multiple places in the module system.
{
  qcfractal-server = ./qcfractal-server.nix;
  qcfractal-compute = ./qcfractal-compute.nix;
}
