# tests/default.nix
#
# Evaluation tests for the QCFractal NixOS modules.
#
# Run all tests:
#   nix-build tests -A all
#
# Run one test:
#   nix-build tests -A server-defaults
#   nix-build tests -A assertion-user-mismatch

{
  pkgs ? import <nixpkgs> { },
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Stub packages injected via nixpkgs.overlays — the only safe extension point
  # when using eval-config.nix, which already sets nixpkgs.pkgs internally.
  # We only need to stub the two packages referenced by mkPackageOption.
  # ---------------------------------------------------------------------------
  stubOverlay = final: prev: {
    qcfractal =
      pkgs.runCommand "qcfractal-stub" { }
        "mkdir -p $out/bin && touch $out/bin/qcfractal-server";
    qcfractalcompute =
      pkgs.runCommand "qcfractalcompute-stub" { }
        "mkdir -p $out/bin && touch $out/bin/qcfractal-compute-manager";
  };

  # Silence the stateVersion warning that fires on every eval-config.nix call.
  noStateVersionWarning = {
    system.stateVersion = lib.mkDefault "26.11";
  };

  # ---------------------------------------------------------------------------
  # Full NixOS evaluation via eval-config.nix.
  # This loads all NixOS base modules (systemd, networking, users, assertions,
  # postgresql, …) so every option our modules write to already exists.
  # ---------------------------------------------------------------------------
  nixosEval =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit lib;
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ stubOverlay ]; }
        noStateVersionWarning
      ]
      ++ modules;
    };

  evalServer =
    extraConfig:
    (nixosEval [
      ../nixos-modules/qcfractal-server.nix
      extraConfig
    ]).config;

  evalCompute =
    extraConfig:
    (nixosEval [
      ../nixos-modules/qcfractal-compute.nix
      extraConfig
    ]).config;

  # ---------------------------------------------------------------------------
  # check: boolean expression → pass/fail derivation.
  # $out must be a directory because symlinkJoin requires all paths to be
  # directories — it creates symlinks for each file found inside them.
  # ---------------------------------------------------------------------------
  check =
    name: assertion:
    pkgs.runCommand "test-${name}" { } (
      if assertion then "echo 'PASS: ${name}' && mkdir $out" else "echo 'FAIL: ${name}' >&2 && exit 1"
    );

  # ---------------------------------------------------------------------------
  # assertFails: verifies that a given nixosEval call throws when its
  # assertions are checked.  Forcing system.build.toplevel triggers the
  # NixOS assertions module, which throws on any failed assertion.
  # ---------------------------------------------------------------------------
  assertFails =
    name: evalCall:
    let
      result = builtins.tryEval (builtins.seq evalCall.config.system.build.toplevel true);
    in
    check name (!result.success);

  # Real (unstubbed) package set, used only by the overlay contract tests
  # below.  Applied here rather than relying on the caller so that
  # `nix-build tests -A all` works with a plain <nixpkgs>.
  overlaidPkgs = pkgs.extend (import ../overlays).qcfractal;

in
rec {
  # ==========================================================================
  # Overlay contract
  #
  # The rest of this file stubs pkgs.qcfractal / pkgs.qcfractalcompute, so it
  # cannot notice if the overlay stops providing them.  That is exactly the
  # gap that let the VM tests break while these tests stayed green, hence
  # these two.  Evaluation only — nothing is built.
  # ==========================================================================

  # mkPackageOption in both modules resolves against the *top level* of pkgs,
  # not python3Packages.
  overlay-toplevel-packages = check "overlay-toplevel-packages" (
    overlaidPkgs ? qcfractal
    && overlaidPkgs ? qcfractalcompute
    && overlaidPkgs.qcfractal == overlaidPkgs.python3Packages.qcfractal
    && overlaidPkgs.qcfractalcompute == overlaidPkgs.python3Packages.qcfractalcompute
  );

  # Both modules invoke the package via lib.getExe, which falls back to the
  # package *name* when meta.mainProgram is unset — and neither console script
  # is named after its package.
  overlay-main-programs = check "overlay-main-programs" (
    lib.hasSuffix "/bin/qcfractal-server" (lib.getExe overlaidPkgs.qcfractal)
    && lib.hasSuffix "/bin/qcfractal-compute-manager" (lib.getExe overlaidPkgs.qcfractalcompute)
  );

  # ==========================================================================
  # Server module — correct configurations
  # ==========================================================================

  # Disabled: no services should be created.
  server-disabled = check "server-disabled" (
    let
      cfg = evalServer { };
    in
    !(cfg.systemd.services ? qcfractal) && !(cfg.systemd.services ? qcfractal-init-db)
  );

  # Enabled with defaults: both services present, postgresql wired up.
  server-defaults = check "server-defaults" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
    in
    cfg.systemd.services ? qcfractal
    && cfg.systemd.services ? qcfractal-init-db
    && cfg.services.postgresql.enable == true
    && cfg.services.postgresql.ensureDatabases == [ "qcfractal" ]
  );

  # createLocally = false: postgresql must not be touched.
  server-remote-db = check "server-remote-db" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          database.createLocally = false;
          database.host = "db.example.com";
        };
      };
    in
    cfg.services.postgresql.enable == false
  );

  # openFirewall = true: port appears in allowedTCPPorts.
  server-open-firewall = check "server-open-firewall" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          openFirewall = true;
          api.port = 7777;
        };
      };
    in
    builtins.elem 7777 cfg.networking.firewall.allowedTCPPorts
  );

  # openFirewall = false (default): port must not appear.
  server-no-firewall = check "server-no-firewall" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
    in
    !(builtins.elem 7777 cfg.networking.firewall.allowedTCPPorts)
  );

  # Custom port with openFirewall.
  server-custom-port = check "server-custom-port" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          openFirewall = true;
          api.port = 8888;
        };
      };
    in
    builtins.elem 8888 cfg.networking.firewall.allowedTCPPorts
  );

  # WorkingDirectory matches stateDir.
  server-state-dir = check "server-state-dir" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
    in
    cfg.systemd.services.qcfractal.serviceConfig.WorkingDirectory == "/var/lib/qcfractal"
  );

  # Custom stateDir is respected.
  server-custom-state-dir = check "server-custom-state-dir" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          stateDir = "/srv/qcfractal";
        };
      };
    in
    cfg.systemd.services.qcfractal.serviceConfig.WorkingDirectory == "/srv/qcfractal"
  );

  # System user and group are created.
  server-user-created = check "server-user-created" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
    in
    cfg.users.users ? qcfractal
    && cfg.users.users.qcfractal.isSystemUser == true
    && cfg.users.groups ? qcfractal
  );

  # ==========================================================================
  # Server module — assertion violations (must throw during evaluation)
  # ==========================================================================

  # user != database.user with createLocally should be rejected.
  assertion-user-mismatch = assertFails "assertion-user-mismatch" (nixosEval [
    ../nixos-modules/qcfractal-server.nix
    {
      services.qcfractal = {
        enable = true;
        user = "qcfractal";
        database.createLocally = true;
        database.user = "different-user";
      };
    }
  ]);

  # createLocally = false but socket path: should be rejected.
  assertion-socket-without-local = assertFails "assertion-socket-without-local" (nixosEval [
    ../nixos-modules/qcfractal-server.nix
    {
      services.qcfractal = {
        enable = true;
        database.createLocally = false;
        database.host = "/run/postgresql";
      };
    }
  ]);

  # ==========================================================================
  # Compute module — correct configurations
  # ==========================================================================

  compute-disabled = check "compute-disabled" (
    let
      cfg = evalCompute { };
    in
    !(cfg.systemd.services ? qcfractalcompute)
  );

  compute-defaults = check "compute-defaults" (
    let
      cfg = evalCompute {
        services.qcfractalCompute.enable = true;
      };
    in
    cfg.systemd.services ? qcfractalcompute
    &&
      cfg.systemd.services.qcfractalcompute.serviceConfig.WorkingDirectory == "/var/lib/qcfractalcompute"
  );

  compute-user-created = check "compute-user-created" (
    let
      cfg = evalCompute {
        services.qcfractalCompute.enable = true;
      };
    in
    cfg.users.users ? qcfractalcompute
    && cfg.users.users.qcfractalcompute.isSystemUser == true
    && cfg.users.groups ? qcfractalcompute
  );

  # Programs listed in executor.programs appear on the service's PATH.
  compute-programs-in-path = check "compute-programs-in-path" (
    let
      fakePsi4 = pkgs.runCommand "psi4-stub" { } "mkdir -p $out/bin && touch $out/bin/psi4";
      cfg = evalCompute {
        services.qcfractalCompute = {
          enable = true;
          executor.programs = [ fakePsi4 ];
        };
      };
    in
    builtins.elem fakePsi4 cfg.systemd.services.qcfractalcompute.path
  );

  # ==========================================================================
  # Convenience target: build all tests at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "qcfractal-module-tests";
    paths = [
      overlay-toplevel-packages
      overlay-main-programs
      server-disabled
      server-defaults
      server-remote-db
      server-open-firewall
      server-no-firewall
      server-custom-port
      server-state-dir
      server-custom-state-dir
      server-user-created
      assertion-user-mismatch
      assertion-socket-without-local
      compute-disabled
      compute-defaults
      compute-user-created
      compute-programs-in-path
    ];
  };
}
