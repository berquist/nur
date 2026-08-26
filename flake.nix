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
    #   nix flake metadata github:Nix-QChem/NixOS-QChem --json | jq -r '.locks.nodes.nixpkgs.locked.rev'
    #
    # Pinning it by hand rather than reading nixos-qchem's lock at eval time is
    # deliberate: flakes offer no supported way to reach a transitive input's
    # locked revision, and `follows` cannot express "match the dependency".
    nixpkgs-qchem.url = "github:NixOS/nixpkgs/ac6b2166e7a9375683b8e98f860f273222337b16";

    # cclib is not in nixpkgs and upstream carries its own flake, so take it
    # from there rather than repackaging.  Only overlays.default is used — a
    # plain final: prev: function — so following our inputs is free, exactly as
    # for nixos-qchem above.
    #
    # The two `follows` are also no-ops today, and deliberately so: cclib's own
    # flake.lock already pins nixpkgs 3e41b24 and nixos-qchem faad404, which are
    # the two revisions pinned above.  Stating them keeps that alignment from
    # drifting silently when either input is bumped — if it does drift, cclib
    # gets built against a nixpkgs its CI never saw.
    #
    # It matters more than it looks: cclib's nix/cclib.nix promotes the whole
    # `bridges` extra (psi4, pyscf, iodata, biopython, trexio, openbabel) into
    # hard dependencies, so building it means building Psi4 unless the
    # nix-qchem cache is hit — see cclibPkgs below.
    cclib = {
      url = "github:cclib/cclib/release-1.9";
      inputs.nixpkgs.follows = "nixpkgs-qchem";
      inputs.qchem.follows = "nixos-qchem";
    };
  };

  # Binary caches.
  #
  #   nix-qchem      NixOS-QChem's own Hydra output.  Psi4 and CFOUR are large;
  #                  fetch binaries rather than compiling from source.
  #   nur-berquist   this repo's, populated by .github/workflows/build.yml from
  #                  `just ci-build` on every push to main and nightly.  It is
  #                  where the packages nixpkgs does not carry come from, and
  #                  since the qchem set is rebuilt against the compute
  #                  worker's interpreter (see qchemPkgs below), it is also the
  #                  only cache that has *that* Psi4.
  #
  # Note that Nix ignores extra-substituters unless the invoking user is in
  # trusted-users.  Without that, `nix flake check` silently builds Psi4 from
  # source no matter how correct the pinning above is — look for "warning:
  # ignoring untrusted flake configuration setting" before blaming the hashes.
  nixConfig = {
    extra-substituters = [
      "https://nix-qchem.cachix.org"
      "https://nur-berquist.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-qchem.cachix.org-1:ZjRh1PosWRj7qf3eukj4IxjhyXx6ZwJbXvvFk3o3Eos="
      "nur-berquist.cachix.org-1:Hoz7CuoAaFYOUxiy5zcrHEM82xJKjilI24ly0W+1kq4="
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
        #   inputs.nur-berquist.nixosModules.aiida
        nixosModules = import ./nixos-modules;

        # Overlays
        #
        # Our Python packages (pkgs.python313Packages.qcfractal, etc.):
        #   inputs.nur-berquist.overlays.qcfractal
        #
        # aiida-core, its five plugins and their dependencies
        # (pkgs.aiida-core, pkgs.python313Packages.aiida-cp2k, …):
        #   inputs.nur-berquist.overlays.aiida
        #
        # dotdrop (pkgs.dotdrop):
        #   inputs.nur-berquist.overlays.dotdrop
        #
        # harmonwig (pkgs.harmonwig) — but only usable when composed *after*
        # cclib's own overlay, which supplies its cclib; see pkgs/harmonwig:
        #   inputs.nur-berquist.overlays.harmonwig
        #
        # morfeus, QMzyme and the cheminformatics dependencies nixpkgs lacks
        # (pkgs.morfeus-ml, pkgs.python313Packages.mdanalysis, …):
        #   inputs.nur-berquist.overlays.cheminformatics
        #
        # DBSTEP, aqme, ccreg and digichem (pkgs.dbstep, …) — like harmonwig,
        # usable only when composed after cclib's overlay, and after
        # overlays.cheminformatics, which supplies their other dependencies:
        #   inputs.nur-berquist.overlays.cheminformatics-cclib
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

          # The interpreter the compute worker runs.  QCEngine imports a Python
          # QC program *into the worker process*, so a program built for any
          # other Python is unusable — nixos-modules/qcfractal-compute.nix
          # asserts on exactly that.  Programs follow the worker rather than the
          # other way round, because the worker's Python is this repo's pin and
          # is shared with the whole QCArchive family, while a QC program is one
          # package that can be rebuilt.
          #
          # Read off the package instead of spelling "python313" a fourth time,
          # so the two cannot drift.
          workerPython = pkgs'.qcfractalcompute.pythonModule;

          # ...and the attribute naming the *same version* inside nixpkgs-qchem.
          # It has to be selected there rather than passed in from pkgs': an
          # interpreter from our nixpkgs is a different derivation, and handing
          # it to the qchem overlay would drag our whole stdenv into every QC
          # program's closure.
          qchemPythonAttr = "python${lib.replaceStrings [ "." ] [ "" ] workerPython.pythonVersion}";

          # Psi4 for the compute tests.
          #
          # Apart from the interpreter, this reproduces NixOS-QChem's own
          # instantiation exactly — its pinned nixpkgs, its overlay, and the
          # config its flake sets — because that is what nix-qchem.cachix.org
          # was populated from.  Any *further* deviation (our nixpkgs, or a
          # missing config.qchem-config) changes the derivation hash again.
          #
          # The interpreter override is a deviation, and it is not free: while
          # the worker's pin and nixpkgs-qchem's default `python3` disagree,
          # Psi4 and its Python closure miss the cache and build from source.
          # That is the price of the invariant, and it is temporary in the
          # obvious way — the override becomes a no-op the moment the two agree
          # again, and the cache comes back with it.
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
          # Taking Psi4 from a different package set than the VM nodes is fine:
          # a QC program only has to be an executable on the worker's PATH.
          #
          # It is *not* fine to instead fold nixos-qchem.overlays.qchem into
          # pkgs' and take Psi4 from there.  Not because the overlay would
          # disturb anything — it would not; every attribute it writes is
          # namespaced under cfg.prefix, which defaults to "qchem", and the
          # python3 it overrides is qchem.python3, so python313Packages and both
          # our families are untouched by it.  The reason is the one above:
          # pkgs' is built from *our* nixpkgs with no qchem-config, and Psi4
          # built against those is a different derivation from the one the cache
          # holds.  Re-exporting the overlay for consumers, which the `flake`
          # block above does, is a separate matter and carries no such cost.
          qchemPkgs = import inputs.nixpkgs-qchem {
            inherit system;
            overlays = [
              # Must come *before* the qchem overlay, which hangs every Python
              # QC program off `super.python3` — psi4 is
              # `toPythonApplication qchem.python3.pkgs.psi4`, and qchem.python3
              # is `super.python3` plus qchem's packageOverrides.  Rewriting
              # python3 here is therefore the whole of the retarget: nothing
              # downstream names a version.
              #
              # Only python3 needs it.  The qchem overlay reads no other
              # interpreter attribute, and in particular never `python3Packages`
              # — which in nixpkgs aliases the *versioned* set and so would not
              # follow this anyway.
              (_final: prev: {
                python3 =
                  prev.${qchemPythonAttr} or (throw ''
                    nixpkgs-qchem has no ${qchemPythonAttr}, which is the
                    interpreter services.qcfractalCompute would run
                    (Python ${workerPython.pythonVersion}).  Either move the
                    nixpkgs-qchem pin to a revision that still carries it, or
                    move this repo's Python pin to one it does.
                  '');
              })
              inputs.nixos-qchem.overlays.qchem
            ];
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

          # Five packages here need cclib, and cclib's overlay needs the qchem
          # set: nix/overlay.nix there reads final.qchem.python3.pkgs.psi4.
          # Building onto qchemPkgs rather than pkgs' keeps that to one Psi4
          # instead of two — everything else about NixOS-QChem's instantiation
          # is still reproduced, so only the interpreter override above costs
          # anything, and it costs it once.
          #
          # cclib's overlay overrides the *top-level* python3 rather than
          # pythonPackagesExtensions, so it cannot perturb python313Packages and
          # the QCArchive and AiiDA families are untouched.  Note it lands on
          # the python3 the override above installed, so these five follow the
          # worker's interpreter too — which is what the repo's python313 pin
          # wanted of them anyway.
          #
          # The three overlays taken from ./overlays are exactly those whose
          # packages resolve cclib.  `cheminformatics` is included not because
          # anything in it needs cclib — nothing does — but because it is where
          # morfeus-ml, colour-science, lwreg, configurables and openprattle
          # come from, and cheminformatics-cclib reaches them through
          # final.python3.pkgs.
          #
          # `aiida` is deliberately *not* in this list, even though
          # aiida-gaussian would become buildable if it were.  Adding it would
          # rebuild aiida-core and its whole closure against the year-old
          # nixpkgs NixOS-QChem pins instead of ours, which is both expensive
          # and a second, silently divergent AiiDA.  See
          # pkgs/aiida-gaussian/default.nix.
          #
          # Only defined where NixOS-QChem has outputs; its flake hardcodes
          # x86_64-linux and optAVX implies an x86 -march.
          cclibPkgs =
            let
              ours = import ./overlays;
            in
            if system == "x86_64-linux" then
              qchemPkgs.extend (
                lib.composeManyExtensions [
                  inputs.cclib.overlays.default
                  ours.harmonwig
                  ours.cheminformatics
                  ours.cheminformatics-cclib
                ]
              )
            else
              null;

          # NWChem needs no flake input — it is in nixpkgs, and so cached — but
          # it is Linux-only, and a VM test could not run anywhere else anyway.
          nwchem = if pkgs'.stdenv.hostPlatform.isLinux then pkgs'.nwchem else null;

          vmTests = import ./tests/qcarchive/vm.nix {
            pkgs = pkgs';
            inherit psi4 nwchem;
          };

          aiidaVmTests = import ./tests/aiida/vm.nix { pkgs = pkgs'; };

          # Given cclibPkgs rather than pkgs', because that is the only package
          # set in which harmonwig has a cclib; see ./tests/harmonwig and the
          # cclibPkgs binding above.
          harmonwigTests = if cclibPkgs != null then import ./tests/harmonwig { pkgs = cclibPkgs; } else null;

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
          #
          # The five cclib-dependent packages are replaced rather than
          # inherited: the ones in nurAttrs come from the bare ./overlays and
          # carry meta.broken because ./overlays cannot reach the cclib flake
          # input.  These are the working ones.  `nix build .#dbstep` therefore
          # succeeds while `nix-build -A dbstep` does not, which is the same
          # split the Psi4-backed VM checks already live with.
          #
          # aiida-gaussian is the one cclib dependant *not* replaced here; see
          # the cclibPkgs binding above for why.
          #
          # Broken derivations are filtered out rather than left to fail.
          # `nix flake check` forces every member of `packages`, and forcing a
          # meta.broken derivation throws — so leaving `aiida-gaussian` in would
          # take the whole check down, and so would the four below on any system
          # where cclibPkgs is null.  They stay reachable through
          # legacyPackages, which flake check does not force, and which answers
          # with nixpkgs' own "marked as broken" message rather than an
          # attribute-not-found.
          packages =
            lib.filterAttrs (_: v: lib.isDerivation v && !(v.meta.broken or false)) nurAttrs
            // lib.optionalAttrs (cclibPkgs != null) {
              inherit (cclibPkgs)
                harmonwig
                aqme
                ccreg
                dbstep
                digichem-core
                metallogen
                ;
              # molcat is deliberately absent, for the same reason
              # aiida-gaussian is: `nix flake check` forces every attribute of
              # `packages`, and molcat has no licence at all — no LICENSE file,
              # no metadata field — so ../pkgs/molcat marks it
              # `lib.licenses.unfree` and nixpkgs refuses to evaluate it.
              # Naming it here would take the whole check down with a
              # "refusing to evaluate" throw.
              #
              # It stays reachable through legacyPackages and through
              # python313Packages, neither of which flake check forces, so
              # `nix build .#legacyPackages.x86_64-linux.molcat` still works for
              # anyone who has set allowUnfree.
            };

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
              pkgs.cachix
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
          # AiiDA module evaluation tests (likewise fast and stubbed):
          #   nix build .#checks.x86_64-linux.eval-aiida
          #
          # Cheminformatics overlay evaluation tests (likewise; nothing real is
          # built, including the packages under test):
          #   nix build .#checks.x86_64-linux.eval-cheminformatics
          #
          # chemtools/materials overlay evaluation tests (likewise stubbed):
          #   nix build .#checks.x86_64-linux.eval-chemtools
          #
          # dotdrop integration tests (no VM, but they build the real package):
          #   nix build .#checks.x86_64-linux.dotdrop
          #
          # harmonwig integration tests — no VM either, but they build harmonwig
          # and therefore cclib, and so exist only where NixOS-QChem does:
          #   nix build .#checks.x86_64-linux.harmonwig
          #
          # AiiDA VM tests.  The first four need only nixpkgs; the CP2K plugin
          # round trip additionally needs a CP2K, so it is x86_64-linux only:
          #   nix build .#checks.x86_64-linux.vm-aiida-daemon-local-db
          #   nix build .#checks.x86_64-linux.vm-aiida-workchain-arithmetic
          #   nix build .#checks.x86_64-linux.vm-aiida-daemon-rabbitmq
          #   nix build .#checks.x86_64-linux.vm-aiida-daemon-sqlite
          #   nix build .#checks.x86_64-linux.vm-aiida-plugin-cp2k
          #
          # And aiida-core's own SSH transport suite, which needs a real sshd
          # and a real login shell, so it cannot run in the package's check
          # phase — see the comment on the test:
          #   nix build .#checks.x86_64-linux.vm-aiida-transports-ssh
          #
          # VM integration tests (require KVM and real packages):
          #   nix build .#checks.x86_64-linux.vm-server-local-db
          #   nix build .#checks.x86_64-linux.vm-server-open-firewall
          #   nix build .#checks.x86_64-linux.vm-server-remote-db
          #
          # The NWChem round trip needs no flake input — NWChem is in nixpkgs —
          # so it is defined on any Linux system:
          #   nix build .#checks.x86_64-linux.vm-compute-nwchem-singlepoint
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

            # The same, for the AiiDA module.  A separate check rather than a
            # second path into `eval`, so that a failure names which module set
            # broke without having to read the build log.
            eval-aiida = tests.aiida.all;

            # The cheminformatics overlays.  Not a module suite at all — these
            # assert how ../overlays wires the cclib split, which is silent when
            # it goes wrong.  See tests/cheminformatics/default.nix.
            eval-cheminformatics = tests.cheminformatics.all;

            # The chemtools and materials overlays.  Same shape as the line
            # above and for the same reason — the two failures worth catching
            # here (a `chemfiles` that resolves to itself, a pymatgen repair
            # that leaks into the package set) are both silent.  See
            # tests/chemtools/default.nix.
            eval-chemtools = tests.chemtools.all;

            # dotdrop integration tests — no VM, but they do build dotdrop and
            # run upstream's tests-ng scripts against the installed binary.
            dotdrop = tests.dotdrop.all;

            # VM tests — prefixed "vm-" for easy selection.
            vm-server-local-db = vmTests.server-local-db;
            vm-server-open-firewall = vmTests.server-open-firewall;
            vm-server-remote-db = vmTests.server-remote-db;

            vm-aiida-daemon-local-db = aiidaVmTests.daemon-local-db;
            vm-aiida-workchain-arithmetic = aiidaVmTests.workchain-arithmetic;
            vm-aiida-daemon-rabbitmq = aiidaVmTests.daemon-rabbitmq;
            vm-aiida-daemon-sqlite = aiidaVmTests.daemon-sqlite;
            vm-aiida-transports-ssh = aiidaVmTests.transports-ssh;
          }
          // lib.optionalAttrs (nwchem != null) {
            vm-compute-nwchem-singlepoint = vmTests.compute-nwchem-singlepoint;
          }
          // lib.optionalAttrs (psi4 != null) {
            vm-compute-connects = vmTests.compute-connects;
            vm-compute-authenticated = vmTests.compute-authenticated;
            vm-compute-singlepoint = vmTests.compute-singlepoint;
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            # nixpkgs' cp2k declares platforms = [ "x86_64-linux" ].  Guarded on
            # the system string rather than on cp2k.meta.available, because
            # reading that attribute forces the derivation — which is the thing
            # that is not guaranteed to evaluate elsewhere.
            vm-aiida-plugin-cp2k = aiidaVmTests.plugin-cp2k;
          }
          // lib.optionalAttrs (harmonwigTests != null) {
            harmonwig = harmonwigTests.all;
          };
        };
    };
}
