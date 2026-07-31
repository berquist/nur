# pkgs/qcfractal-python/default.nix
#
# Nixpkgs overlay adding the four QCFractal Python packages.
# Must be a function  final: prev: { ... }  (standard overlay convention).
#
# Top-level attributes (pkgs.qcfractal, pkgs.qcfractalcompute, …) are built
# against prev.python312Packages to avoid touching the fixed-point for the
# interpreter itself and causing infinite recursion.
#
# pythonPackagesExtensions injects the same packages into every pythonX.pkgs
# set so that  python312.withPackages (p: [ p.qcfractal ])  also works.

final: prev:

let
  callPkg = prev.python312Packages.callPackage;
in
{
  qcportal = callPkg ./qcportal.nix { };
  qcfractal = callPkg ./qcfractal.nix { };
  qcfractalcompute = callPkg ./qcfractalcompute.nix { };
  qcarchivetesting = callPkg ./qcarchivetesting.nix { };

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pself: _psuper: {
      qcportal = pself.callPackage ./qcportal.nix { };
      qcfractal = pself.callPackage ./qcfractal.nix { };
      qcfractalcompute = pself.callPackage ./qcfractalcompute.nix { };
      qcarchivetesting = pself.callPackage ./qcarchivetesting.nix { };
    })
  ];
}
