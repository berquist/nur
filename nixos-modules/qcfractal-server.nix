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
  #
  # FractalConfig requires three fields that are secrets and therefore must not
  # be rendered into the world-readable Nix store: database.password,
  # api.secret_key and api.jwt_secret_key.  They are supplied from the
  # environment instead -- see runtimeSecrets below.
  baseConfig = {
    name = cfg.serverName;
    loglevel = cfg.logLevel;
    enable_security = cfg.enableSecurity;
    allow_unauthenticated_read = cfg.allowUnauthenticatedRead;

    api = {
      inherit (cfg.api) host port;
    };

    database = {
      own = false;
      inherit (cfg.database) host port;
      database_name = cfg.database.name;
      username = cfg.database.user;
    };
  }
  // lib.optionalAttrs (cfg.logFile != null) { logfile = cfg.logFile; };

  # recursiveUpdate rather than //: with a shallow merge, an extraConfig.api
  # holding only `host` would replace the whole api block and silently drop the
  # generated port.
  serverConfig = lib.generators.toYAML { } (lib.recursiveUpdate baseConfig cfg.extraConfig);

  serverConfigFile = pkgs.writeText "qcf_config.yaml" serverConfig;

  # qcfractal reads its configuration through pydantic-settings, which maps
  # QCF_<SECTION>__<FIELD> onto <section>.<field> (env_prefix "QCF_",
  # env_nested_delimiter "__", case-insensitive).  FractalConfig lists
  # env_settings ahead of init_settings in settings_customise_sources, so the
  # environment overrides qcf_config.yaml -- hence anything the user pinned
  # through extraConfig is left alone below.
  extraApi = cfg.extraConfig.api or { };
  extraDatabase = cfg.extraConfig.database or { };

  # Flask/JWT signing keys.  Upstream's `qcfractal-server init-config`
  # generates these randomly; do the same, once, into a 0600 file under
  # stateDir so they survive restarts without ever entering the store.
  secretsFile = "${cfg.stateDir}/secrets.env";

  generatedSecrets =
    lib.optional (!(extraApi ? secret_key)) "QCF_API__SECRET_KEY"
    ++ lib.optional (!(extraApi ? jwt_secret_key)) "QCF_API__JWT_SECRET_KEY";

  randomSecret = "${pkgs.coreutils}/bin/head -c 32 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w 0";

  # Loading the keys is separated from generating them because the two have
  # different callers.  The units may create the file; anything a human runs
  # must only ever read it, since run under sudo it would create the file owned
  # by root and the service could no longer read its own keys.
  loadApiSecrets = lib.optionalString (generatedSecrets != [ ]) ''
    set -a
    # shellcheck source=/dev/null
    . '${secretsFile}'
    set +a
  '';

  apiSecretsSetup =
    lib.optionalString (generatedSecrets != [ ]) ''
      if [ ! -f '${secretsFile}' ]; then
        ( umask 077
          {
            ${lib.concatStringsSep "\n      " (
              map (v: "printf '${v}=%s\\n' \"$(${randomSecret})\"") generatedSecrets
            )}
          } > '${secretsFile}'
        )
      fi
    ''
    + loadApiSecrets;

  # database.password is required by FractalConfig even when it is meaningless.
  dbPasswordSetup =
    if extraDatabase ? password then
      ""
    else if cfg.database.passwordFile != null then
      ''
        QCF_DATABASE__PASSWORD="$(< '${cfg.database.passwordFile}')"
        export QCF_DATABASE__PASSWORD
        export PGPASSWORD="$QCF_DATABASE__PASSWORD"
      ''
    else
      ''
        # Peer authentication over the local Unix socket ignores the password,
        # but the field still has to validate as a string.
        export QCF_DATABASE__PASSWORD=""
      '';

  # Shared preamble for both units; they load the same configuration.
  runtimeSecrets = apiSecretsSetup + dbPasswordSetup;

  # `qcfractal-server` is not only a daemon: user management, backups and
  # restores all run it by hand, and with enableSecurity there is no
  # declarative route to creating the first account -- users live in
  # PostgreSQL, so a deployment is not finished until someone has run
  # `user add`.  Doing that correctly means reproducing what the units set up
  # first, because FractalConfig validates in full before the CLI touches the
  # database: without the generated api keys and a database.password it exits
  # on a validation error that says nothing about either.  Reconstructing that
  # from this file is not a reasonable thing to ask, so ship it.
  manageScript = pkgs.writeShellApplication {
    name = "qcfractal-manage";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      # Privileges first: stateDir is 0750, so to anyone else the secrets file
      # below is not merely unreadable but unstattable, and checking for it
      # first would answer "does not exist" to what is really "not allowed".
      if [ "$(id -u -n)" != '${cfg.user}' ]; then
        if [ "$(id -u)" -ne 0 ]; then
          echo "qcfractal-manage: run as root or as ${cfg.user}." >&2
          exit 1
        fi
        exec runuser -u '${cfg.user}' -- "$0" "$@"
      fi

      if [ ! -f '${secretsFile}' ]; then
        echo "qcfractal-manage: '${secretsFile}' does not exist." >&2
        echo "Start qcfractal.service once before managing the server." >&2
        exit 1
      fi
      ${loadApiSecrets}
      ${dbPasswordSetup}
      exec ${lib.getExe cfg.package} --config='${cfg.stateDir}/qcf_config.yaml' "$@"
    '';
  };

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
          Read at service start and exported as QCF_DATABASE__PASSWORD (and
          PGPASSWORD), so it never appears in the Nix store.
          Not needed when using local Unix-socket peer authentication: the
          password is then set to the empty string, which QCFractal requires
          to be present but peer authentication ignores.
        '';
      };

      autoUpgrade = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `qcfractal-server upgrade-db` automatically before starting the
          server, applying any Alembic migrations the packaged version needs.

          Left false by default deliberately.  A QCFractal upgrade that adds
          migrations makes the server refuse to start with "Database needs
          migration", and upstream's own message says to migrate only *after
          backing up* — a schema migration on a large production database is
          not something to trigger implicitly from a `nixos-rebuild switch`.

          With this false, the migration is a manual step:

          ```
          systemctl start qcfractal-upgrade-db.service
          ```

          The unit is defined either way; this option only controls whether it
          is pulled in automatically and ordered before
          {file}`qcfractal.service`.  Enable it for throwaway, development or
          well-backed-up deployments where unattended upgrades are wanted.
        '';
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra settings merged recursively into the generated qcf_config.yaml.
        Values here override module-derived settings of the same name, leaving
        sibling keys alone — {option}`extraConfig.api.host` does not disturb
        the generated {option}`api.port`.
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
        inherit (cfg) group;
        home = cfg.stateDir;
        description = "QCFractal server daemon";
      };
    };

    users.groups = lib.mkIf (cfg.group == "qcfractal") {
      qcfractal = { };
    };

    # Create the role but deliberately NOT the database.
    #
    # `qcfractal-server init-db` bootstraps the schema in PostgresHarness.
    # create_database, and that only happens on the branch that creates the
    # database itself -- if the database already exists it logs "already
    # exists, so I am leaving it alone" and returns without creating any
    # tables or stamping an alembic revision.  `start` then fails its
    # check_db_revision with "Database needs migration", forever.
    #
    # `upgrade-db` cannot repair that either: the alembic history's root
    # revision alters existing tables rather than creating the schema, so
    # there is no migration path from an empty database.  Letting init-db
    # own creation is the only bootstrap route, which is also what the
    # upstream setup guide assumes.
    services.postgresql = lib.mkIf localDB {
      enable = lib.mkDefault true;
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureClauses.createdb = true;
        }
      ];
    };

    # Bootstrapping an account is a required step on any server with
    # enableSecurity, so the tool for it belongs on the PATH of whoever has to
    # do it rather than behind a nix-shell invocation.
    environment.systemPackages = [ manageScript ];

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
          ${runtimeSecrets}
          exec ${lib.getExe cfg.package} --config="$CFG" init-db
        '';
      };
    };

    # Apply Alembic migrations.  Always defined so that an administrator can
    # run it by hand after taking a backup -- which is what upstream's
    # "Database needs migration. Please run `qcfractal-server upgrade-db`
    # (after backing up!)" is asking for -- but only wired into the boot
    # sequence when database.autoUpgrade is set.
    #
    # Ordered after init-db because upgrade-db requires an existing, populated
    # database: it refuses with "Database at ... does not exist for upgrading?"
    # otherwise, and it reads the config file that init-db installs.  On a
    # freshly bootstrapped database init-db has already stamped the alembic
    # head, so this is a no-op rather than a second bootstrap path.
    systemd.services.qcfractal-upgrade-db = {
      description = "QCFractal - apply database schema migrations";
      wantedBy = lib.optional cfg.database.autoUpgrade "multi-user.target";
      after = [
        "network.target"
        "qcfractal-init-db.service"
      ]
      ++ lib.optional localDB "postgresql.target";
      requires = [ "qcfractal-init-db.service" ] ++ lib.optional localDB "postgresql.target";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;

        ExecStart = pkgs.writeShellScript "qcfractal-upgrade-db" ''
          set -euo pipefail
          ${runtimeSecrets}
          exec ${lib.getExe cfg.package} \
            --config='${cfg.stateDir}/qcf_config.yaml' \
            upgrade-db
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
      ++ lib.optional cfg.database.autoUpgrade "qcfractal-upgrade-db.service"
      ++ lib.optional localDB "postgresql.target";
      requires = [
        "qcfractal-init-db.service"
      ]
      ++ lib.optional cfg.database.autoUpgrade "qcfractal-upgrade-db.service"
      ++ lib.optional localDB "postgresql.target";

      # Bound the restart loop.  systemd's default start limit (5 failures in
      # 10s) can never trigger with RestartSec=15s, so a permanently broken
      # configuration would otherwise restart every 15 seconds forever, never
      # reaching "failed" and never surfacing as an error.  Ten attempts over
      # ten minutes still rides out a transient database restart.
      startLimitIntervalSec = 600;
      startLimitBurst = 10;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "15s";

        ExecStart = pkgs.writeShellScript "qcfractal-start" ''
          set -euo pipefail
          ${runtimeSecrets}
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
