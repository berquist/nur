# overlays/default.nix
#
# Exposed as the `overlays` reserved key in default.nix and re-exported
# by flake.nix as `self.overlays`.
#
# Each value is a standard  final: prev: { ... }  overlay function.
# Add new overlays here as additional attributes; default.nix composes
# them all via lib.composeManyExtensions.
{
  # dotdrop is a standalone CLI application — nothing here imports it as a
  # library — so it is a plain top-level package rather than a
  # pythonPackagesExtensions entry, and it follows the default `python3`
  # instead of the 3.13 pin the QCArchive set is stuck on.  Keeping it in its
  # own overlay is what lets a consumer take `overlays.dotdrop` without
  # dragging in qcportal and its closure.
  dotdrop = final: _prev: {
    dotdrop = final.python3Packages.callPackage ../pkgs/dotdrop { };
  };

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
    # python313Packages above (not rebuilds), and they are what
    # lib.mkPackageOption pkgs "qcfractal" in the NixOS modules resolves
    # against — without them, `services.qcfractal.package` fails with
    # "qcfractal cannot be found in pkgs" the moment a VM node or a real
    # system evaluates the module.
    #
    # python313 rather than python3: qcportal does not import on 3.14, which
    # nixpkgs-unstable now defaults to.  See pkgs/qcportal/default.nix for the
    # mechanism and ../default.nix for why following the default would break
    # the NixOS modules and the VM tests outright.
    #
    # Keep this list, and the interpreter, in sync with the `inherit (py)` list
    # in ../default.nix — the overlay-python-pin eval test asserts they agree.
    inherit (final.python313Packages)
      parsl
      qcportal
      qcfractal
      qcfractalcompute
      qcarchivetesting
      ;
  };
}
