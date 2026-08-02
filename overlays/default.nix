# overlays/default.nix
#
# Exposed as the `overlays` reserved key in default.nix and re-exported
# by flake.nix as `self.overlays`.
#
# Each value is a standard  final: prev: { ... }  overlay function.
# Add new overlays here as additional attributes; default.nix composes
# them all via lib.composeManyExtensions.
{
  # Injects all QCArchive/QCFractal Python packages into every pythonX.pkgs
  # set via pythonPackagesExtensions.  This is what makes
  # python3.withPackages (p: [ p.qcfractal p.qcportal ... ]) work.
  #
  # pself is the fixed point of the *extended* Python package set, so
  # pself.qcportal inside the qcfractal derivation resolves to the local
  # package automatically — no manual inherit threading needed.
  qcfractal = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pself: _psuper: {
        parsl = pself.callPackage ../pkgs/parsl { };
        qcportal = pself.callPackage ../pkgs/qcportal { };
        qcfractal = pself.callPackage ../pkgs/qcfractal { };
        qcfractalcompute = pself.callPackage ../pkgs/qcfractalcompute { };
        qcarchivetesting = pself.callPackage ../pkgs/qcarchivetesting { };
      })
    ];

    # Top-level aliases. These are the *same* derivations as the entries in
    # python3Packages above (not rebuilds), and they are what
    # lib.mkPackageOption pkgs "qcfractal" in the NixOS modules resolves
    # against — without them, `services.qcfractal.package` fails with
    # "qcfractal cannot be found in pkgs" the moment a VM node or a real
    # system evaluates the module.
    #
    # Keep this list in sync with the `inherit (py)` list in ../default.nix.
    inherit (final.python3Packages)
      parsl
      qcportal
      qcfractal
      qcfractalcompute
      qcarchivetesting
      ;
  };
}
