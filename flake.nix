{
  description = "berquist's personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    nixpkgs-qchem.url = "github:NixOS/nixpkgs/afb4584a80bbf779ce0f691509ff902d188c2b3d";
  };

  # Binary cache for NixOS-QChem (Psi4 and CFOUR are large; fetch binaries
  # rather than compiling from source).
  #
  # Note that Nix ignores extra-substituters unless the invoking user is in
  # trusted-users.  Without that, `nix flake check` silently builds Psi4 from
  # source no matter how correct the pinning above is — look for "warning:
  # ignoring untrusted flake configuration setting" before blaming the hashes.
  nixConfig = {
    extra-substituters = [ "https://nix-qchem.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-qchem.cachix.org-1:ZjRh1PosWRj7qf3eukj4IxjhyXx6ZwJbXvvFk3o3Eos="
    ];
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [ inputs.git-hooks.flakeModule ];

      # -----------------------------------------------------------------------
      # System-agnostic outputs
      # -----------------------------------------------------------------------
      flake = {
        # NixOS modules
        #
        # Import into your system flake as:
        #   inputs.nur-berquist.nixosModules.qcfractal-server
        #   inputs.nur-berquist.nixosModules.qcfractal-compute
        nixosModules = import ./nixos-modules;

        # Overlays
        #
        # Our Python packages (pkgs.python313Packages.qcfractal, etc.):
        #   inputs.nur-berquist.overlays.qcfractal
        #
        # dotdrop (pkgs.dotdrop):
        #   inputs.nur-berquist.overlays.dotdrop
        #
        # NixOS-QChem re-exported for convenience (pkgs.qchem.*):
        #   inputs.nur-berquist.overlays.qchem
        #
        # All at once:
        #   inputs.nur-berquist.overlays.default
        overlays = (import ./overlays) // {
          inherit (inputs.nixos-qchem.overlays) qchem;
          default = inputs.nixpkgs.lib.composeManyExtensions (
            [ inputs.nixos-qchem.overlays.qchem ] ++ builtins.attrValues (import ./overlays)
          );
        };
      };

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          inherit (inputs.nixpkgs) lib;

          # pkgs' has our overlays applied — required by the eval tests (for
          # runCommand and for pkgs.dotdrop), and by the VM tests
          # (testers.nixosTest uses pkgs directly as the node package set).
          #
          # Composed from *all* of ./overlays, matching what default.nix does,
          # so that a package added there needs no second edit here.
          #
          # Distinct from the `pkgs` argument above, which flake-parts hands us
          # unmodified: legacyPackages below must stay un-overlaid, because
          # default.nix applies the overlays itself.
          pkgs' = import inputs.nixpkgs {
            inherit system;
            overlays = builtins.attrValues (import ./overlays);
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
          qchemPkgs = import inputs.nixpkgs-qchem {
            inherit system;
            overlays = [ inputs.nixos-qchem.overlays.qchem ];
            config.allowUnfree = true;
            # Matches the arguments NixOS-QChem's flake passes; allowEnv = false
            # keeps NIXQC_* environment variables from perturbing the hash.
            config.qchem-config = import "${inputs.nixos-qchem}/cfg.nix" {
              allowEnv = false;
              optAVX = true;
            };
          };

          # NixOS-QChem targets x86_64-linux only (its flake hardcodes that
          # system, and optAVX implies an x86 -march), so the three checks that
          # need Psi4 are defined only there.  They need KVM anyway.
          psi4 = if system == "x86_64-linux" then qchemPkgs.qchem.psi4 else null;

          vmTests = import ./tests/qcarchive/vm.nix {
            pkgs = pkgs';
            inherit psi4;
          };

          tests = import ./tests { pkgs = pkgs'; };

          nurAttrs = import ./default.nix { inherit pkgs; };
        in
        {
          # -------------------------------------------------------------------
          # Legacy packages (NUR convention: all top-level derivations, flat).
          # Driven by default.nix, which applies our overlays internally so that
          # the derivations here are identical to what python313.withPackages
          # returns.
          # -------------------------------------------------------------------
          legacyPackages = nurAttrs;

          # Flake-style packages (derivations only, filtered).
          packages = lib.filterAttrs (_: v: lib.isDerivation v) nurAttrs;

          # -------------------------------------------------------------------
          # Formatting and linting, wired up as git hooks.
          #
          # The generated .pre-commit-config.yaml is written by the devShell's
          # shellHook and is gitignored — this block is the source of truth.
          # Run them by hand with `just hooks`.
          # -------------------------------------------------------------------
          pre-commit.settings = {
            # prek rather than the default pre-commit: git-hooks.nix supports
            # it directly (`usingPrek = cfg.package.pname == "prek"`), so the
            # generated .pre-commit-config.yaml, the installed git hook and
            # `just hooks` all go through the same runner.
            package = pkgs.prek;

            hooks = {
              # Nix-scoped: these three carry their own `files` filters.
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;

              # Whole-tree: no `files` filter, so these run against every
              # tracked file — YAML workflows, the Justfile, docs and shell
              # scripts included, not just Nix.
              check-merge-conflicts.enable = true;
              trim-trailing-whitespace = {
                enable = true;
                # Trailing whitespace is *significant* in a unified diff: a
                # blank context line is a single space, and stripping it makes
                # the hunk fail to apply.  Stripping pkgs/parsl/conftest.patch
                # breaks the parsl build.
                excludes = [ "\\.patch$" ];
              };
            };
          };

          devShells.default = pkgs.mkShell {
            # installationScript rather than config.pre-commit.devShell: it
            # writes .pre-commit-config.yaml and installs the git hook, which is
            # all we want from the module — the tools themselves are listed
            # explicitly below.
            shellHook = config.pre-commit.installationScript;
            packages = [
              pkgs.just
              pkgs.nixfmt
              pkgs.statix
              pkgs.deadnix
              pkgs.prek
              pkgs.jq
            ];
          };

          # -------------------------------------------------------------------
          # Checks
          #
          # QCFractal module evaluation tests (fast, no VM, no real packages):
          #   nix build .#checks.x86_64-linux.eval
          #
          # dotdrop integration tests (no VM, but they build the real package):
          #   nix build .#checks.x86_64-linux.dotdrop
          #
          # VM integration tests (require KVM and real packages):
          #   nix build .#checks.x86_64-linux.vm-server-local-db
          #   nix build .#checks.x86_64-linux.vm-server-open-firewall
          #   nix build .#checks.x86_64-linux.vm-server-remote-db
          #
          # The three compute checks additionally need Psi4, so they are defined
          # only on x86_64-linux (the sole system NixOS-QChem's flake has
          # outputs for):
          #   nix build .#checks.x86_64-linux.vm-compute-connects
          #   nix build .#checks.x86_64-linux.vm-compute-authenticated
          #   nix build .#checks.x86_64-linux.vm-compute-singlepoint
          #
          # All at once (adds the pre-commit check the git-hooks module
          # contributes):
          #   nix flake check
          # -------------------------------------------------------------------
          checks = {
            # Evaluation tests — always fast, no real packages needed.
            eval = tests.qcarchive.all;

            # dotdrop integration tests — no VM, but they do build dotdrop and
            # run upstream's tests-ng scripts against the installed binary.
            dotdrop = tests.dotdrop.all;

            # VM tests — prefixed "vm-" for easy selection.
            vm-server-local-db = vmTests.server-local-db;
            vm-server-open-firewall = vmTests.server-open-firewall;
            vm-server-remote-db = vmTests.server-remote-db;
          }
          // lib.optionalAttrs (psi4 != null) {
            vm-compute-connects = vmTests.compute-connects;
            vm-compute-authenticated = vmTests.compute-authenticated;
            vm-compute-singlepoint = vmTests.compute-singlepoint;
          };
        };
    };
}
