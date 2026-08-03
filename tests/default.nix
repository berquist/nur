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
    qcfractalcompute = pkgs.runCommand "qcfractalcompute-stub" {
      # The compute module builds a python env from cfg.package.pythonModule
      # for QCEngine's out-of-process program discovery, and withPackages
      # only accepts packages carrying this attribute.
      passthru.pythonModule = pkgs.python3;
    } "mkdir -p $out/bin && touch $out/bin/qcfractal-compute-manager";
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
  # not python313Packages.
  overlay-toplevel-packages = check "overlay-toplevel-packages" (
    overlaidPkgs ? qcfractal
    && overlaidPkgs ? qcfractalcompute
    && overlaidPkgs.qcfractal == overlaidPkgs.python313Packages.qcfractal
    && overlaidPkgs.qcfractalcompute == overlaidPkgs.python313Packages.qcfractalcompute
  );

  # The interpreter the QCArchive packages are pinned to is spelled out twice —
  # `py` in ../default.nix and the top-level `inherit` in ../overlays/default.nix
  # — and nothing forces the two to agree.  If they drift, `nix-build -A
  # qcfractal` and `pkgs.qcfractal` silently become different derivations and
  # every consumer builds the closure twice.
  overlay-python-pin = check "overlay-python-pin" (
    let
      nur = import ../default.nix { inherit pkgs; };
    in
    nur.qcfractal == overlaidPkgs.qcfractal
    && nur.qcfractalcompute == overlaidPkgs.qcfractalcompute
    && nur.qcportal == overlaidPkgs.qcportal
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
    && (
      let
        users = cfg.services.postgresql.ensureUsers;
      in
      builtins.length users == 1
      && (builtins.head users).name == "qcfractal"
      # init-db issues the CREATE DATABASE itself, so the role needs CREATEDB.
      && (builtins.head users).ensureClauses.createdb == true
    )
  );

  # The database must NOT be pre-created: qcfractal-server init-db only
  # bootstraps the schema on the code path where it creates the database
  # itself, and there is no alembic path from an empty database.
  server-db-not-precreated = check "server-db-not-precreated" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
    in
    cfg.services.postgresql.ensureDatabases == [ ]
  );

  # The migration unit always exists so it can be run by hand after a backup,
  # but by default nothing pulls it in and the server does not wait on it.
  server-upgrade-db-manual-by-default = check "server-upgrade-db-manual-by-default" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
      upgrade = cfg.systemd.services.qcfractal-upgrade-db;
    in
    cfg.systemd.services ? qcfractal-upgrade-db
    && upgrade.wantedBy == [ ]
    && !(builtins.elem "qcfractal-upgrade-db.service" cfg.systemd.services.qcfractal.requires)
    # It must still be ordered after init-db, so that a manual run on a fresh
    # machine cannot race the bootstrap that creates the config and database.
    && builtins.elem "qcfractal-init-db.service" upgrade.requires
  );

  # autoUpgrade = true: pulled in at boot and the server waits for it.
  server-upgrade-db-auto = check "server-upgrade-db-auto" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          database.autoUpgrade = true;
        };
      };
      upgrade = cfg.systemd.services.qcfractal-upgrade-db;
      server = cfg.systemd.services.qcfractal;
    in
    upgrade.wantedBy == [ "multi-user.target" ]
    && builtins.elem "qcfractal-upgrade-db.service" server.requires
    && builtins.elem "qcfractal-upgrade-db.service" server.after
  );

  # The migration runs as the service user and needs the same secrets as the
  # other two units: FractalConfig validation happens before it touches the
  # database, so a missing api.secret_key fails it just as it fails `start`.
  server-upgrade-db-secrets = check "server-upgrade-db-secrets" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
      s = cfg.systemd.services.qcfractal-upgrade-db.serviceConfig.ExecStart.text;
    in
    lib.hasInfix "QCF_API__SECRET_KEY" s
    && lib.hasInfix "QCF_API__JWT_SECRET_KEY" s
    && lib.hasInfix "QCF_DATABASE__PASSWORD" s
    && lib.hasInfix "upgrade-db" s
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

  # FractalConfig requires database.password, api.secret_key and
  # api.jwt_secret_key, none of which may be rendered into the store.  Both
  # units must therefore supply all three from the environment; omitting any
  # one of them makes qcfractal-server die during config validation before it
  # ever touches the database.
  server-required-secrets = check "server-required-secrets" (
    let
      cfg = evalServer {
        services.qcfractal.enable = true;
      };
      scriptOf = unit: cfg.systemd.services.${unit}.serviceConfig.ExecStart.text;
      exportsAll =
        unit:
        let
          s = scriptOf unit;
        in
        lib.hasInfix "QCF_API__SECRET_KEY" s
        && lib.hasInfix "QCF_API__JWT_SECRET_KEY" s
        && lib.hasInfix "QCF_DATABASE__PASSWORD" s;
    in
    exportsAll "qcfractal-init-db" && exportsAll "qcfractal"
  );

  # Generated signing keys must land outside the store, in stateDir.
  server-secrets-outside-store = check "server-secrets-outside-store" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          stateDir = "/srv/qcfractal";
        };
      };
      s = cfg.systemd.services.qcfractal-init-db.serviceConfig.ExecStart.text;
    in
    lib.hasInfix "/srv/qcfractal/secrets.env" s && lib.hasInfix "umask 077" s
  );

  # extraConfig wins: pydantic-settings puts env_settings ahead of the config
  # file, so the module must not export values the user pinned by hand.
  server-secrets-extraconfig-wins = check "server-secrets-extraconfig-wins" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          extraConfig.api = {
            host = "127.0.0.1";
            port = 7777;
            secret_key = "pinned";
            jwt_secret_key = "pinned-jwt";
          };
        };
      };
      s = cfg.systemd.services.qcfractal.serviceConfig.ExecStart.text;
    in
    !(lib.hasInfix "QCF_API__SECRET_KEY" s) && !(lib.hasInfix "QCF_API__JWT_SECRET_KEY" s)
  );

  # database.passwordFile is read at start time and never inlined.
  server-password-file = check "server-password-file" (
    let
      cfg = evalServer {
        services.qcfractal = {
          enable = true;
          database.createLocally = false;
          database.host = "db.example.com";
          database.passwordFile = "/run/secrets/qcfractal-db";
        };
      };
      s = cfg.systemd.services.qcfractal.serviceConfig.ExecStart.text;
    in
    lib.hasInfix ''QCF_DATABASE__PASSWORD="$(< '/run/secrets/qcfractal-db')"'' s
    && lib.hasInfix "PGPASSWORD" s
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

  # Regression guard.  QCEngine program discovery is *not* in-process: the
  # manager shells out to `python3 qcengine_list.py`, and that script turns a
  # failed `import qcengine` into an empty program list rather than an error.
  # Without PYTHONPATH the child is a bare interpreter, every executor
  # discovers zero programs, and the manager exits with "has no available
  # programs" — with nothing pointing at the real cause.
  #
  # PATH deliberately does NOT carry the python env: the wrapper around
  # qcfractal-compute-manager prepends its own bare interpreter and would win.
  compute-python-path-for-discovery = check "compute-python-path-for-discovery" (
    let
      cfg = evalCompute {
        services.qcfractalCompute.enable = true;
      };
      pythonPath = cfg.systemd.services.qcfractalcompute.environment.PYTHONPATH or null;
    in
    pythonPath != null && lib.hasInfix "-env/lib/python" pythonPath
  );

  # ==========================================================================
  # Convenience target: build all tests at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "qcfractal-module-tests";
    paths = [
      overlay-toplevel-packages
      overlay-python-pin
      overlay-main-programs
      server-disabled
      server-defaults
      server-db-not-precreated
      server-upgrade-db-manual-by-default
      server-upgrade-db-auto
      server-upgrade-db-secrets
      server-remote-db
      server-required-secrets
      server-secrets-outside-store
      server-secrets-extraconfig-wins
      server-password-file
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
      compute-python-path-for-discovery
    ];
  };
}
