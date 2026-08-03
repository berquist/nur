{
  description = "berquist's personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # NixOS-QChem provides Psi4, CFOUR, NWChem, and many other QC codes.
    # Packages live under pkgs.qchem.* once the overlay is applied.
    #
    # We use only pure values from this input — overlays.qchem (a plain
    # final: prev: function) and cfg.nix (a file read through its outPath) —
    # never its instantiated `packages` output.  Nothing we touch depends on
    # which nixpkgs it resolves to, so following ours is free and keeps
    # flake.lock a node smaller.  See nixpkgs-qchem below for the reason its
    # own outputs are avoided.
    nixos-qchem = {
      url = "github:Nix-QChem/NixOS-QChem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The nixpkgs revision NixOS-QChem's own flake.lock pins, duplicated here
    # explicitly.
    #
    # nix-qchem.cachix.org is populated by NixOS-QChem's Hydra, which builds
    # against *that* revision with *its* nixpkgs config.  Reproducing both is
    # the only way our Psi4 derivation hashes match what the cache holds;
    # anything else means compiling Psi4's whole closure (CheMPS2, adcc,
    # libint, …) from source.
    #
    # This must be bumped in lockstep with the nixos-qchem input above.  Read
    # the target revision out of the input's own lock:
    #
    #   nix flake metadata github:Nix-QChem/NixOS-QChem --json \
    #     | jq -r '.locks.nodes.nixpkgs.locked.rev'
    #
    # Pinning it by hand rather than reading nixos-qchem's lock at eval time is
    # deliberate: flakes offer no supported way to reach a transitive input's
    # locked revision, and `follows` cannot express "match the dependency".
    nixpkgs-qchem.url = "github:NixOS/nixpkgs/3e41b24abd260e8f71dbe2f5737d24122f972158";
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
      nixpkgs-qchem,
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
      #
      # The two compute checks additionally need Psi4, so they are defined only
      # on x86_64-linux (the sole system NixOS-QChem's flake has outputs for):
      #   nix build .#checks.x86_64-linux.vm-compute-connects
      #   nix build .#checks.x86_64-linux.vm-compute-singlepoint
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

          # Psi4 for the compute tests.
          #
          # This reproduces NixOS-QChem's own instantiation exactly — its pinned
          # nixpkgs, its overlay, and the config its flake sets — because that
          # is what nix-qchem.cachix.org was populated from.  Any deviation
          # (our nixpkgs, or a missing config.qchem-config) changes the
          # derivation hash and sends Psi4's closure to a from-source build.
          #
          # Do NOT simplify this to `nixos-qchem.packages.${system}.psi4`.  That
          # output is a filterAttrs over the *entire* qchem set, so selecting a
          # single package forces the predicate for every other one — and the
          # predicate's `builtins.tryEval` guard only catches `throw` and
          # `assert`, not signature drift like "called with unexpected arguments
          # 'blas', 'lapack' and 'scalapack'".  One broken package anywhere in
          # NixOS-QChem then takes down our whole `checks` output.  Selecting
          # qchem.psi4 from our own instantiation forces only Psi4.
          #
          # Taking Psi4 from a different package set than the VM nodes is fine —
          # and in fact preferable.  The nixos-qchem overlay extends python3's
          # packageOverrides, so folding it into pkgs' would rebuild qcfractal,
          # qcportal and their whole dependency closure against a different
          # Python package set, changing even the tests that never touch Psi4.
          # A QC program only has to be an executable on the worker's PATH.
          qchemPkgs = import nixpkgs-qchem {
            inherit system;
            overlays = [ nixos-qchem.overlays.qchem ];
            config.allowUnfree = true;
            # Matches the arguments NixOS-QChem's flake passes; allowEnv = false
            # keeps NIXQC_* environment variables from perturbing the hash.
            config.qchem-config = import "${nixos-qchem}/cfg.nix" {
              allowEnv = false;
              optAVX = true;
            };
          };

          # NixOS-QChem targets x86_64-linux only (its flake hardcodes that
          # system, and optAVX implies an x86 -march), so the two checks that
          # need Psi4 are defined only there.  They need KVM anyway.
          psi4 = if system == "x86_64-linux" then qchemPkgs.qchem.psi4 else null;

          vmTests = import ./tests/vm.nix {
            pkgs = pkgs';
            inherit psi4;
          };
        in
        {
          # Evaluation tests — always fast, no real packages needed.
          eval = (import ./tests { pkgs = pkgs'; }).all;

          # VM tests — prefixed "vm-" for easy selection.
          vm-server-local-db = vmTests.server-local-db;
          vm-server-open-firewall = vmTests.server-open-firewall;
          vm-server-remote-db = vmTests.server-remote-db;
        }
        // nixpkgs.lib.optionalAttrs (psi4 != null) {
          vm-compute-connects = vmTests.compute-connects;
          vm-compute-singlepoint = vmTests.compute-singlepoint;
        }
      );
    };
}
