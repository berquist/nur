# Excerpt showing how to wire berquist/nur into your personal-cluster-config
# flake.nix.  Merge this with your existing inputs/outputs.

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Your NUR — provides QCFractal modules, packages, and the QChem overlay.
    nur-berquist = {
      url = "github:berquist/nur";
      inputs.nixpkgs.follows = "nixpkgs";
      # nixos-qchem inside the NUR also follows the same nixpkgs:
      # inputs.nixos-qchem.inputs.nixpkgs.follows = "nixpkgs";
      # (only needed if you want to pin it explicitly)
    };

    # ... your other inputs (nixos-hardware, agenix, etc.) ...
  };

  outputs =
    {
      # Unused in this excerpt, but kept because a real system flake almost
      # always binds it — this file is meant to be copied, not evaluated.
      # deadnix: skip
      self,
      nixpkgs,
      nur-berquist,
      ...
    }:
    {

      nixosConfigurations.meyeri = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # ── Overlays ──────────────────────────────────────────────────────
          # Apply the combined overlay: adds pkgs.qchem.* (NixOS-QChem) and
          # pkgs.qcfractal / pkgs.qcfractalcompute (QCFractal Python packages).
          { nixpkgs.overlays = [ nur-berquist.overlays.default ]; }

          # Or, if you only want one of the two overlays:
          # { nixpkgs.overlays = [ nur-berquist.overlays.qcfractal ]; }
          # { nixpkgs.overlays = [ nur-berquist.overlays.qchem ]; }

          # ── NixOS modules ─────────────────────────────────────────────────
          # Import only the services you actually enable on this host.
          # Each module is independent; you do not need both.
          nur-berquist.nixosModules.qcfractal-server # services.qcfractal.*
          nur-berquist.nixosModules.qcfractal-compute # services.qcfractalCompute.*

          # ── Your existing configuration ────────────────────────────────────
          ./hosts/meyeri/configuration.nix
          # ... hardware-configuration.nix, etc. ...
        ];
      };
    };
}
