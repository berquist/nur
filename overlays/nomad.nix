# overlays/nomad.nix — NOMAD Oasis.
#
# This overlay deliberately does *not* follow the pythonPackagesExtensions
# pattern the QCArchive packages use (see ./default.nix).  That pattern injects
# into every pythonX.pkgs set, which is right for packages that only add
# things.  NOMAD does not only add: it needs fastapi 0.136, httpx 0.27, plotly
# 5, beautifulsoup4 4.12.3, rdflib 5.0 and elasticsearch 7 — all of them older
# than what nixpkgs ships, and all of them load-bearing elsewhere in nixpkgs.
# Pushing those globally would rebuild a large fraction of the package set and
# would break qcportal's and qcfractal's closures next door, for the benefit of
# exactly one application.
#
# So NOMAD gets its own interpreter, `pkgs.nomadPython`, and every downgrade is
# confined to it.  The cost is a second Python closure in the store; the
# alternative is a repo where adding NOMAD breaks the other half of the repo.
#
# python312, not python3 and not the python313 the QCArchive side pins.
#
# python3 is out because nixpkgs-unstable has moved it to 3.14, which is well
# ahead of anything in this closure (upstream's own image is
# uv:0.9-python3.13, and the oldest thing here is rdflib 5.0.0, from 2020).
#
# 3.12 rather than 3.13 comes down to one package: nixpkgs marks pymatgen
# `disabled = pythonAtLeast "3.13"`, and nomad-lab requires
# pymatgen>=2025.10.7 unconditionally — the materials normalizer is not
# optional.  Every one of pymatgen's own dependencies does build on 3.13 (numba,
# vtk, moyopy and spglib were all checked), so the marker reads as nixpkgs-side
# conservatism rather than a real break; but clearing another repo's `disabled`
# flag to gain nothing but a version number is a bad trade.  Revisit when
# nixpkgs lifts it.
final: _prev: {
  # `self` is what makes this a real package set rather than a set of packages
  # built against a different interpreter: without it, pythonModule on every
  # package below would still point at the unmodified python312, and
  # nomadPython.withPackages would refuse to combine them.
  nomadPython = final.python312.override {
    self = final.nomadPython;
    packageOverrides = import ../pkgs/nomad/python-overrides.nix;
  };

  # Top-level alias, load-bearing rather than a convenience: the NixOS module
  # uses lib.mkPackageOption pkgs "nomad-lab", which resolves against the top
  # level of pkgs.  Without it, services.nomad-oasis fails with "nomad-lab
  # cannot be found in pkgs" the moment a VM node or a real system evaluates.
  #
  # This is the *same* derivation as nomadPython.pkgs.nomad-lab, not a rebuild;
  # the overlay-nomad-python-pin eval test asserts that.
  #
  # Note the name: pkgs.nomad and services.nomad in nixpkgs are HashiCorp
  # Nomad, which is unrelated.  Ours is pkgs.nomad-lab and
  # services.nomad-oasis, and neither may be shortened.
  inherit (final.nomadPython.pkgs) nomad-lab;
}
