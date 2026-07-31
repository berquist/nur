# tests/default.nix
#
# Evaluation tests for the QCFractal NixOS modules.
#
# These tests verify that the modules evaluate correctly — options typecheck,
# assertions fire when they should, and the generated systemd/postgresql config
# looks right — without booting a VM.
#
# Run all tests:
#   nix-build tests
#
# Run a specific test:
#   nix-build tests -A server-defaults
#   nix-build tests -A assertion-user-mismatch
#
# How it works
# ------------
# lib.evalModules runs the NixOS module system on a list of modules and returns
# the evaluated config.  We do NOT need a real pkgs for this: the module uses
# pkgs for mkPackageOption and lib.getExe, so we stub those with a minimal fake.
# The stub only needs to satisfy what the module actually calls; it does not need
# to be a full nixpkgs.
#
# The test derivations themselves are built with pkgs (from the argument), but
# only to get access to lib and runCommandNoCC for driving the assertions.

{
  pkgs ? import <nixpkgs> { },
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Minimal pkgs stub for evalModules.
  # mkPackageOption references pkgs.<name>, and the generated ExecStart scripts
  # call lib.getExe cfg.package, so we provide a fake derivation.
  # ---------------------------------------------------------------------------
  fakeDrv = name: pkgs.runCommandNoCC name { } "mkdir -p $out/bin && touch $out/bin/${name}";

  fakePkgs = {
    inherit lib;
    qcfractal = fakeDrv "qcfractal-server";
    qcfractalcompute = fakeDrv "qcfractal-compute-manager";
    writeText = pkgs.writeText;
    writeShellScript = pkgs.writeShellScript;
    # tmpfiles rules use builtins only — no pkgs needed there.
  };

  # ---------------------------------------------------------------------------
  # evalModules wrapper: evaluates one or both modules with the given config.
  # Returns config.assertions, config.services.*, config.systemd.*, etc.
  # ---------------------------------------------------------------------------
  evalServer =
    extraConfig:
    (lib.evalModules {
      modules = [
        ../nixos-modules/qcfractal-server.nix
        { _module.args.pkgs = fakePkgs; }
        extraConfig
      ];
    }).config;

  evalCompute =
    extraConfig:
    (lib.evalModules {
      modules = [
        ../nixos-modules/qcfractal-compute.nix
        { _module.args.pkgs = fakePkgs; }
        extraConfig
      ];
    }).config;

  # ---------------------------------------------------------------------------
  # Test helper: build a derivation that runs an expression and fails if it
  # returns false or throws.
  # ---------------------------------------------------------------------------
  check =
    name: assertion:
    pkgs.runCommandNoCC "test-${name}" { } (
      if assertion then "echo 'PASS: ${name}' && touch $out" else "echo 'FAIL: ${name}' >&2 && exit 1"
    );

  # ---------------------------------------------------------------------------
  # assertFails: verify that evalModules throws (for assertion-violation tests).
  # builtins.tryEval catches most evaluation errors.
  # ---------------------------------------------------------------------------
  assertFails =
    name: thunk:
    let
      result = builtins.tryEval (builtins.seq thunk true);
    in
    check name (!result.success);

in
rec {
  # ==========================================================================
  # Server module — evaluation with defaults
  # ==========================================================================

  # Disabled module should produce no systemd services.
  server-disabled = check "server-disabled" (
    let
      cfg = evalServer { };
    in
    !(cfg.systemd.services ? qcfractal) && !(cfg.systemd.services ? qcfractal-init-db)
  );

  # Enabled module should produce both services and enable postgresql.
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

  # With createLocally = false, postgresql must not be touched.
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

  # openFirewall should add the port.
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

  # openFirewall = false (default) must not add anything.
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

  # The generated systemd unit for the server should reference the state dir.
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

  # User and group are created with the right attributes when using defaults.
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
  # Server module — assertion violations (these must throw)
  # ==========================================================================

  # Mismatched user / database.user with createLocally = true should fail.
  assertion-user-mismatch = assertFails "assertion-user-mismatch" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          user = "qcfractal";
          database.createLocally = true;
          database.user = "different-user";
        };
      };
    in
    # Force evaluation of the assertions.
    builtins.seq cfg.assertions true
  );

  # createLocally = false but host still set to socket path should fail.
  assertion-socket-without-local = assertFails "assertion-socket-without-local" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          database.createLocally = false;
          database.host = "/run/postgresql";
        };
      };
    in
    builtins.seq cfg.assertions true
  );

  # ==========================================================================
  # Compute module — evaluation with defaults
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

  # Programs added to executor.programs appear in the service's path.
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
  # Convenience target: build all tests at once
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
