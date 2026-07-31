# nixos-modules/qcfractal-server.nix
#
# NixOS module for the QCFractal server (web API + Alembic DB layer).
# Import this file directly, or reference it as
#   inputs.nur.nixosModules.qcfractal-server
# from your system flake.
#
# This module is intentionally independent of the compute worker module.
# You do not need to import both; each can be used on its own machine.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.qcfractal;

  # True when we should wire up a local PostgreSQL instance for the server.
  # Mirrors the idiom from services.gitea: "/run/postgresql" as host value
  # is the canonical signal that peer-authenticated local Postgres is intended.
  localDB = cfg.enable && cfg.database.createLocally && cfg.database.host == "/run/postgresql";

  # Generate the qcf_config.yaml that qcfractal-server reads at startup.
  # Password is intentionally absent; it is injected at runtime via PGPASSWORD
  # (read from passwordFile) so it never appears in the Nix store.
  serverConfig = lib.generators.toYAML { } (
    {
      name = cfg.serverName;
      loglevel = cfg.logLevel;
      enable_security = cfg.enableSecurity;
      allow_unauthenticated_read = cfg.allowUnauthenticatedRead;

      api = {
        host = cfg.api.host;
        port = cfg.api.port;
      };

      database = {
        own = false;
        host = cfg.database.host;
        port = cfg.database.port;
        database_name = cfg.database.name;
        username = cfg.database.user;
      };
    }
    // lib.optionalAttrs (cfg.logFile != null) { logfile = cfg.logFile; }
    // cfg.extraConfig
  );

  serverConfigFile = pkgs.writeText "qcf_config.yaml" serverConfig;

in
{
  options.services.qcfractal = {

    enable = lib.mkEnableOption "the QCFractal quantum-chemistry server (web API)";

    package = lib.mkPackageOption pkgs "qcfractal" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "qcfractal";
      description = "System user that runs qcfractal-server.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "qcfractal";
      description = "System group for the qcfractal service.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/qcfractal";
      description = "Directory that holds persistent server state and the generated config file.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "QCFractal Server";
      description = "Human-readable name returned by the server info endpoint.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "DEBUG"
        "INFO"
        "WARNING"
        "ERROR"
        "CRITICAL"
      ];
      default = "INFO";
      description = "Logging verbosity.";
    };

    logFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/log/qcfractal/server.log";
      description = "Log file path. null means log only to the systemd journal.";
    };

    enableSecurity = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Require user authentication.
        Disable only for private or ephemeral deployments.
      '';
    };

    allowUnauthenticatedRead = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow unauthenticated clients to read records and datasets.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`services.qcfractal.api.port` in the firewall.

        Leave this false (the default) when the server binds to 127.0.0.1
        or when it sits behind a reverse proxy on the same machine.
        Set it to true when compute workers or clients connect from remote
        hosts and there is no separate proxy handling ingress.
      '';
    };

    api = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = ''
          Address the web API binds to.
          Use "0.0.0.0" to accept connections on all interfaces
          (e.g. when running behind a reverse proxy or serving remote workers).
          The default "127.0.0.1" exposes the API only on loopback.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 7777;
        description = "TCP port the web API listens on.";
      };
    };

    database = {

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Manage a local PostgreSQL database for QCFractal.

          When true (the default) the module enables {option}`services.postgresql`,
          creates the role and database, and connects via the local Unix socket
          at /run/postgresql using peer authentication (no password needed).

          Set to false for advanced use-cases: very large databases (100 GB+)
          or a PostgreSQL instance on a separate machine.  In that case supply
          {option}`database.host`, {option}`database.port`,
          {option}`database.user`, and optionally {option}`database.passwordFile`.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = if cfg.database.createLocally then "/run/postgresql" else "localhost";
        defaultText = lib.literalExpression ''
          if config.services.qcfractal.database.createLocally
          then "/run/postgresql"
          else "localhost"
        '';
        description = ''
          PostgreSQL host or Unix-socket directory.
          A value beginning with "/" is treated by libpq as a socket directory
          rather than a hostname, enabling peer authentication with no password.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port. Ignored when connecting via Unix socket.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "qcfractal";
        description = "PostgreSQL database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "qcfractal";
        description = ''
          PostgreSQL role that QCFractal connects as.
          For local peer-authenticated connections this must match
          {option}`services.qcfractal.user`.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/credentials/qcfractal.service/db-password";
        description = ''
          Path to a file containing the PostgreSQL password.
          Read at service start; supplied to libpq via PGPASSWORD so it
          never appears in the Nix store.
          Not needed when using local Unix-socket peer authentication.
        '';
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra key-value pairs merged into the generated qcf_config.yaml.
        Values here override module-derived settings.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = localDB -> (cfg.user == cfg.database.user);
        message = ''
          services.qcfractal: when database.createLocally is true,
          database.user must match user ("${cfg.user}") because PostgreSQL
          peer authentication maps the OS user name to the role name.
        '';
      }
      {
        assertion = !cfg.database.createLocally -> (cfg.database.host != "/run/postgresql");
        message = ''
          services.qcfractal: database.host is "/run/postgresql" but
          database.createLocally is false.  Either enable createLocally or
          set database.host to the address of your external PostgreSQL server.
        '';
      }
    ];

    users.users = lib.mkIf (cfg.user == "qcfractal") {
      qcfractal = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        description = "QCFractal server daemon";
      };
    };

    users.groups = lib.mkIf (cfg.group == "qcfractal") {
      qcfractal = { };
    };

    services.postgresql = lib.mkIf localDB {
      enable = lib.mkDefault true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.api.port ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 '${cfg.user}' '${cfg.group}' - -"
    ]
    ++ lib.optional (
      cfg.logFile != null
    ) "d '${dirOf cfg.logFile}' 0750 '${cfg.user}' '${cfg.group}' - -";

    # One-shot unit that runs Alembic migrations / schema creation.
    # RemainAfterExit keeps it "active" so qcfractal.service can depend on it
    # and won't restart migrations on every server restart.
    systemd.services.qcfractal-init-db = {
      description = "QCFractal - initialise or migrate the database schema";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optional localDB "postgresql.target";
      requires = lib.optional localDB "postgresql.target";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;

        ExecStart = pkgs.writeShellScript "qcfractal-init-db" ''
          set -euo pipefail
          CFG='${cfg.stateDir}/qcf_config.yaml'
          # Write config on first run; subsequent runs use the persisted copy
          # so that manual edits to the file are preserved.
          if [ ! -f "$CFG" ]; then
            install -m 0640 '${serverConfigFile}' "$CFG"
          fi
          ${lib.optionalString (cfg.database.passwordFile != null) ''
            export PGPASSWORD="$(< '${cfg.database.passwordFile}')"
          ''}
          exec ${lib.getExe cfg.package} --config="$CFG" init-db
        '';
      };
    };

    systemd.services.qcfractal = {
      description = "QCFractal quantum-chemistry server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "qcfractal-init-db.service"
      ]
      ++ lib.optional localDB "postgresql.target";
      requires = [ "qcfractal-init-db.service" ] ++ lib.optional localDB "postgresql.target";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "15s";

        ExecStart = pkgs.writeShellScript "qcfractal-start" ''
          set -euo pipefail
          ${lib.optionalString (cfg.database.passwordFile != null) ''
            export PGPASSWORD="$(< '${cfg.database.passwordFile}')"
          ''}
          exec ${lib.getExe cfg.package} \
            --config='${cfg.stateDir}/qcf_config.yaml' \
            start
        '';

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.stateDir ] ++ lib.optional (cfg.logFile != null) (dirOf cfg.logFile);
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
