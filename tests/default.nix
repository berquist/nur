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
#
# How it works
# ------------
# We use nixos/lib/eval-config.nix to evaluate modules against the full NixOS
# option set.  This gives us systemd.*, networking.*, users.*, services.*,
# and assertions all defined correctly, without needing to boot a VM.
#
# Assertions are enforced by the NixOS assertions module: when an assertion
# fails, accessing config.system.build (or any other fully-evaluated attribute)
# throws.  We use builtins.tryEval to catch that for the "should fail" tests.

{
  pkgs ? import <nixpkgs> { },
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Full NixOS eval.  Loads the complete NixOS module set so that systemd.*,
  # networking.*, users.*, services.postgresql.*, and assertions are all defined.
  #
  # We stub out the package options (qcfractal, qcfractalcompute) with empty
  # derivations so evalModules doesn't try to build anything real.
  # ---------------------------------------------------------------------------
  fakeDrv = name: pkgs.runCommand name { } "mkdir -p $out/bin && touch $out/bin/${name}";

  baseModules = [
    # Provide the full NixOS option set (systemd, users, networking, etc.)
    # without this, options like systemd.services.* don't exist.
    { nixpkgs.hostPlatform = "x86_64-linux"; }
  ];

  nixosEval =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit pkgs lib;
      system = null; # hostPlatform is set via the module above
      modules = baseModules ++ modules;
    };

  evalServer =
    extraConfig:
    (nixosEval [
      ../nixos-modules/qcfractal-server.nix
      {
        nixpkgs.pkgs = pkgs // {
          qcfractal = fakeDrv "qcfractal-server";
        };
      }
      extraConfig
    ]).config;

  evalCompute =
    extraConfig:
    (nixosEval [
      ../nixos-modules/qcfractal-compute.nix
      {
        nixpkgs.pkgs = pkgs // {
          qcfractalcompute = fakeDrv "qcfractal-compute-manager";
        };
      }
      extraConfig
    ]).config;

  # ---------------------------------------------------------------------------
  # check: turns a boolean Nix expression into a build-time test derivation.
  # ---------------------------------------------------------------------------
  check =
    name: assertion:
    pkgs.runCommand "test-${name}" { } (
      if assertion then "echo 'PASS: ${name}' && touch $out" else "echo 'FAIL: ${name}' >&2 && exit 1"
    );

  # ---------------------------------------------------------------------------
  # assertFails: verifies that forcing a config attribute throws.
  # NixOS assertions are checked when config.system.build is forced.
  # builtins.tryEval catches the resulting evaluation error.
  # ---------------------------------------------------------------------------
  assertFails =
    name: getCfg:
    let
      result = builtins.tryEval (builtins.seq (getCfg).system.build.toplevel true);
    in
    check name (!result.success);

in
rec {
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
      nixpkgs.pkgs = pkgs // {
        qcfractal = fakeDrv "qcfractal-server";
      };
    }
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
      nixpkgs.pkgs = pkgs // {
        qcfractal = fakeDrv "qcfractal-server";
      };
    }
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
      fakePsi4 = fakeDrv "psi4";
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
