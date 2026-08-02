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
      # Legacy packages (NUR convention: all top-level derivations, flat).
      # Driven by default.nix, which applies our overlays internally so that
      # the derivations here are identical to what python3.withPackages returns.
      # -----------------------------------------------------------------------
      legacyPackages = forAllSystems (
        system:
        import ./default.nix {
          pkgs = import nixpkgs { inherit system; };
        }
      );

      # Flake-style packages (derivations only, filtered).
      packages = forAllSystems (
        system: nixpkgs.lib.filterAttrs (_: v: nixpkgs.lib.isDerivation v) self.legacyPackages.${system}
      );

      # -----------------------------------------------------------------------
      # NixOS modules
      #
      # Import into your system flake as:
      #   inputs.nur-berquist.nixosModules.qcfractal-server
      #   inputs.nur-berquist.nixosModules.qcfractal-compute
      # -----------------------------------------------------------------------
      nixosModules = import ./nixos-modules;

      # -----------------------------------------------------------------------
      # Overlays
      #
      # Our Python packages (pkgs.python3Packages.qcfractal, etc.):
      #   inputs.nur-berquist.overlays.qcfractal
      #
      # NixOS-QChem re-exported for convenience (pkgs.qchem.*):
      #   inputs.nur-berquist.overlays.qchem
      #
      # Both at once:
      #   inputs.nur-berquist.overlays.default
      # -----------------------------------------------------------------------
      overlays = (import ./overlays) // {
        qchem = nixos-qchem.overlays.qchem;
        default = nixpkgs.lib.composeManyExtensions [
          nixos-qchem.overlays.qchem
          (import ./overlays).qcfractal
        ];
      };

      # -----------------------------------------------------------------------
      # Checks
      #
      # Evaluation tests (fast, no VM, no real packages):
      #   nix build .#checks.x86_64-linux.eval
      #
      # VM integration tests (require KVM and real packages):
      #   nix build .#checks.x86_64-linux.vm-server-local-db
      #   nix build .#checks.x86_64-linux.vm-server-open-firewall
      #   nix build .#checks.x86_64-linux.vm-server-remote-db
      #   nix build .#checks.x86_64-linux.vm-compute-connects
      #
      # All at once:
      #   nix flake check
      # -----------------------------------------------------------------------
      checks = forAllSystems (
        system:
        let
          # pkgs' has our overlay applied — required by both the eval tests
          # (for runCommand) and the VM tests (testers.nixosTest uses pkgs
          # directly as the node package set).
          pkgs' = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.qcfractal ];
          };
          vmTests = import ./tests/vm.nix { pkgs = pkgs'; };
        in
        {
          # Evaluation tests — always fast, no real packages needed.
          eval = (import ./tests { pkgs = pkgs'; }).all;

          # VM tests — prefixed "vm-" for easy selection.
          vm-server-local-db = vmTests.server-local-db;
          vm-server-open-firewall = vmTests.server-open-firewall;
          vm-server-remote-db = vmTests.server-remote-db;
          vm-compute-connects = vmTests.compute-connects;
        }
      );
    };
}
