{
  description = "berquist's personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # NixOS-QChem provides Psi4, CFOUR, NWChem, and many other QC codes.
    # Packages live under pkgs.qchem.* once the overlay is applied.
    nixos-qchem = {
      url = "github:Nix-QChem/NixOS-QChem";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Binary cache for NixOS-QChem (Psi4 and CFOUR are large; fetch binaries
  # rather than compiling from source).
  nixConfig = {
    extra-substituters = [ "https://nix-qchem.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-qchem.cachix.org-1:ZjRh1PosWRj7qf3eukj4IxjhyXx6ZwJbXvvFk3o3Eos="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-qchem,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      # -----------------------------------------------------------------------
      # Legacy packages (NUR convention: all top-level derivations, flat)
      # -----------------------------------------------------------------------
      legacyPackages = forAllSystems (
        system:
        import ./default.nix {
          pkgs = import nixpkgs { inherit system; };
        }
      );

      # Flake-style packages (derivations only, filtered)
      packages = forAllSystems (
        system: nixpkgs.lib.filterAttrs (_: v: nixpkgs.lib.isDerivation v) self.legacyPackages.${system}
      );

      # -----------------------------------------------------------------------
      # NixOS modules
      #
      # Exposed as:
      #   inputs.nur-berquist.nixosModules.qcfractal-server
      #   inputs.nur-berquist.nixosModules.qcfractal-compute
      #
      # Import either or both into your nixosSystem modules list.
      # -----------------------------------------------------------------------
      nixosModules = import ./nixos-modules;

      # -----------------------------------------------------------------------
      # Overlays
      #
      # The QCFractal Python packages overlay (pkgs.qcfractal, etc.):
      #   inputs.nur-berquist.overlays.qcfractal
      #
      # The NixOS-QChem overlay re-exported for convenience (pkgs.qchem.*):
      #   inputs.nur-berquist.overlays.qchem
      #
      # A combined overlay applying both at once:
      #   inputs.nur-berquist.overlays.default
      # -----------------------------------------------------------------------
      overlays = {
        qcfractal = import ./pkgs/qcfractal-python;
        qchem = nixos-qchem.overlays.qchem;
        default = nixpkgs.lib.composeManyExtensions [
          self.overlays.qchem
          self.overlays.qcfractal
        ];
      };
    };
}
