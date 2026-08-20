# nixos-modules/aiida.nix
#
# NixOS module for an AiiDA instance: a PostgreSQL-backed profile and the
# `verdi` daemon that runs its processes.  Import this file directly, or
# reference it as
#   inputs.nur.nixosModules.aiida
# from your system flake.
#
# This module is independent of the qcfractal ones; nothing is shared.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.aiida;

  # True when we should wire up a local PostgreSQL instance.  Mirrors the idiom
  # in ./qcfractal-server.nix, which took it from services.gitea: "/run/postgresql"
  # as the host value is the canonical signal that peer-authenticated local
  # PostgreSQL is intended.
  localDB = cfg.enable && cfg.database.createLocally && cfg.database.host == "/run/postgresql";

  localRabbit = cfg.broker.backend == "core.rabbitmq" && cfg.broker.createLocally;

  # The interpreter environment that actually runs AiiDA.
  #
  # This is the single most important thing in this module, and it is *not*
  # `lib.getExe cfg.package`.  AiiDA finds calculation, parser and workflow
  # plugins through Python entry points, so a plugin is only visible if it lives
  # in the same environment as the aiida-core that looks for it.  Worse, the
  # daemon does not merely import: DaemonClient._verdi_bin in
  # aiida/engine/daemon/client.py does `shutil.which('verdi')` and then has
  # circus spawn `verdi daemon worker` and `verdi daemon broker` as *separate
  # processes*.  Those children re-resolve `verdi` from PATH, so pointing at the
  # bare aiida-core console script would give the workers an interpreter with no
  # plugins in it — and the failure surfaces as "Unknown entry point" on a
  # submitted calculation, nowhere near the cause.
  #
  # Hence: build one env holding aiida-core plus every plugin, put its bin on
  # the unit's PATH, and invoke that.
  pythonEnv = cfg.package.pythonModule.withPackages (_: [ cfg.package ] ++ cfg.plugins);

  verdi = lib.getExe' pythonEnv "verdi";

  # AiiDA appends `.aiida` to each entry of AIIDA_PATH; see
  # aiida/manage/configuration/settings.py.  Everything — config.json, the
  # daemon's pid and socket files, the ZeroMQ broker's state, the file
  # repository — lands under here.
  configDir = "${cfg.stateDir}/.aiida";

  # Built by Config.filepaths() in aiida/manage/configuration/config.py; systemd
  # needs it to track the circus arbiter under Type=forking.
  circusPidFile = "${configDir}/daemon/circus-${cfg.profileName}.pid";

  # `verdi config set` takes strings; booleans have to be spelled the way
  # AiiDA's option parser expects rather than the way Nix prints them.
  configOptionValue = v: if lib.isBool v then (if v then "True" else "False") else toString v;

  applyConfigOptions = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      "${verdi} config set ${lib.escapeShellArg name} ${lib.escapeShellArg (configOptionValue value)}"
    ) cfg.configOptions
  );

  # Read at start rather than interpolated, so the password never enters the
  # store.  It does end up in ${configDir}/config.json, which AiiDA writes under
  # umask 0077 inside a 0700 stateDir -- that is where AiiDA keeps profile
  # credentials and there is no way to run core.psql_dos without it.
  dbPasswordSetup =
    if cfg.database.passwordFile != null then
      ''
        AIIDA_DB_PASSWORD="$(< '${cfg.database.passwordFile}')"
      ''
    else
      ''
        # Peer authentication over the local Unix socket ignores the password,
        # but the storage model still requires the field to be present.
        AIIDA_DB_PASSWORD=""
      '';

  brokerPasswordSetup =
    if cfg.broker.passwordFile != null then
      ''
        AIIDA_BROKER_PASSWORD="$(< '${cfg.broker.passwordFile}')"
      ''
    else
      ''
        AIIDA_BROKER_PASSWORD='${cfg.broker.password}'
      '';

  # `verdi profile setup core.psql_dos` both creates the profile and initialises
  # the storage -- create_profile() calls storage_cls.initialise().  There is no
  # separate schema-creation step the way qcfractal has `init-db`.
  setupScript = pkgs.writeShellScript "aiida-init" ''
    set -euo pipefail

    ${dbPasswordSetup}

    if ! ${verdi} profile show '${cfg.profileName}' >/dev/null 2>&1; then
      ${verdi} profile setup core.psql_dos \
        --non-interactive \
        --profile-name '${cfg.profileName}' \
        --set-as-default \
        --email '${cfg.userEmail}' \
        --first-name '${cfg.firstName}' \
        --last-name '${cfg.lastName}' \
        --institution '${cfg.institution}' \
        --broker '${cfg.broker.backend}' \
        --database-hostname '${cfg.database.host}' \
        --database-port '${toString cfg.database.port}' \
        --database-name '${cfg.database.name}' \
        --database-username '${cfg.database.user}' \
        --database-password "$AIIDA_DB_PASSWORD" \
        --repository-uri 'file://${configDir}/repository/${cfg.profileName}'
    fi

    ${lib.optionalString (cfg.broker.backend == "core.rabbitmq") ''
      # Pin the connection parameters explicitly.  `profile setup --broker
      # core.rabbitmq` calls detect_rabbitmq_config(), which probes localhost
      # with the guest account and silently leaves the profile *without* a
      # broker if that probe fails -- so a deployment pointing at a non-default
      # host or vhost would come up looking healthy and be unable to submit.
      ${brokerPasswordSetup}
      ${verdi} profile configure-broker core.rabbitmq '${cfg.profileName}' \
        --non-interactive \
        --force \
        --broker-protocol '${cfg.broker.protocol}' \
        --broker-host '${cfg.broker.host}' \
        --broker-port '${toString cfg.broker.port}' \
        --broker-username '${cfg.broker.username}' \
        --broker-password "$AIIDA_BROKER_PASSWORD" \
        --broker-virtual-host '${cfg.broker.virtualHost}'
    ''}

    ${applyConfigOptions}

    ${lib.optionalString cfg.setupLocalhost ''
      # The computer AiiDA submits to when nothing else is configured.  Idempotent
      # by the same show-or-create shape as the profile above.
      if ! ${verdi} -p '${cfg.profileName}' computer show '${cfg.localhost.label}' >/dev/null 2>&1; then
        ${verdi} -p '${cfg.profileName}' computer setup \
          --non-interactive \
          --label '${cfg.localhost.label}' \
          --description 'the machine running the AiiDA daemon' \
          --hostname 'localhost' \
          --transport core.local \
          --scheduler core.direct \
          --work-dir '${cfg.localhost.workDir}' \
          --mpirun-command '${cfg.localhost.mpirunCommand}' \
          --mpiprocs-per-machine '${toString cfg.localhost.mpiprocsPerMachine}'
        ${verdi} -p '${cfg.profileName}' computer configure core.local '${cfg.localhost.label}' \
          --non-interactive \
          --safe-interval '${toString cfg.localhost.safeInterval}'
      fi
    ''}
  '';

in
{
  options.services.aiida = {

    enable = lib.mkEnableOption "AiiDA, a workflow manager for computational science";

    package = lib.mkPackageOption pkgs "aiida-core" { };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.python313Packages.aiida-quantumespresso ]";
      description = ''
        AiiDA plugin packages to make available to the daemon.

        These are installed into the same Python environment as
        {option}`services.aiida.package`, which is what makes their entry points
        visible: a plugin in a different environment is invisible to AiiDA, and
        a calculation using it fails at submission with an unknown-entry-point
        error.

        The programs a plugin drives (`pw.x`, `cp2k`, …) are a separate matter —
        add those to {option}`services.aiida.extraPackages`.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.quantum-espresso pkgs.cp2k ]";
      description = ''
        Extra packages to put on the daemon's PATH.

        This is where the simulation codes go when they are run through a
        `core.local` transport on this machine. Codes reached over SSH need
        nothing here.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "aiida";
      description = "System user that runs the AiiDA daemon.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "aiida";
      description = "System group for the AiiDA service.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/aiida";
      description = ''
        Directory holding all persistent AiiDA state.

        Exported as `AIIDA_PATH`, so AiiDA places its configuration directory at
        {file}`''${stateDir}/.aiida` and everything else — the file repository,
        daemon pid and socket files, logs — beneath that.
      '';
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Name of the AiiDA profile this module creates and runs.";
    };

    # All four of these reach `verdi profile setup` as explicit flags, and
    # aiida-core types the last three as `NonEmptyStringParamType` -- so an empty
    # string is rejected outright rather than treated as "unset":
    #
    #     Error: Invalid value for '--institution': Empty string is not valid!
    #
    # There is no way to say "leave it to aiida-core" while still passing the
    # flag, and omitting the flag is not the same thing either: each one is
    # `required=True` with a default that reads `autofill.user.*` out of the
    # config, which this module has not written yet at that point in the script
    # -- so it would fall back to upstream's own `John Doe` at `Unknown`.  Hence
    # `nonEmptyStr` on all three, so setting one to "" fails at evaluation with
    # the option path named rather than at boot inside aiida-init.service.
    userEmail = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "aiida@localhost";
      description = ''
        Email identifying the profile's default user.

        AiiDA uses this as the owner of every node created locally, and it is
        recorded in exported archives, so it is worth setting to something real
        before any data is generated.
      '';
    };

    firstName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "AiiDA";
      description = "First name of the profile's default user.";
    };

    lastName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "Daemon";
      description = "Last name of the profile's default user.";
    };

    institution = lib.mkOption {
      type = lib.types.nonEmptyStr;
      # Upstream's own fallback, for want of anything truer about a machine that
      # is by definition not at one.
      default = "Unknown";
      description = "Institution of the profile's default user.";
    };

    workers = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        Number of daemon worker processes.

        Each worker runs AiiDA processes concurrently; upstream's guidance is to
        stay at or below the number of physical cores. This maps to
        `verdi daemon start -n`.
      '';
    };

    setupLocalhost = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Configure a `localhost` computer using the `core.local` transport and the
        `core.direct` scheduler, so that calculations can run on this machine
        without any further setup.

        Turn this off for a deployment that only ever submits to remote
        computers configured by hand.
      '';
    };

    localhost = {
      label = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Label of the computer created by {option}`setupLocalhost`.";
      };

      workDir = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.stateDir}/scratch";
        defaultText = lib.literalExpression ''"''${config.services.aiida.stateDir}/scratch"'';
        description = ''
          Directory in which calculations run on the local computer.

          This fills up with the working directories of every calculation, so on
          a busy instance it belongs on a filesystem with room rather than
          alongside the database.
        '';
      };

      mpirunCommand = lib.mkOption {
        type = lib.types.str;
        default = "mpirun -np {tot_num_mpiprocs}";
        description = "Template AiiDA uses to launch MPI calculations on the local computer.";
      };

      mpiprocsPerMachine = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = ''
          Default number of MPI ranks per calculation on the local computer.

          Left at 1 rather than derived from the host's core count: the value is
          baked into the stored `Computer` at first boot and is not revisited on
          later activations, so a machine-dependent default would silently
          persist the core count of whichever machine happened to run the setup
          first.
        '';
      };

      safeInterval = lib.mkOption {
        type = lib.types.numbers.nonnegative;
        default = 0.0;
        description = ''
          Minimum seconds between connection attempts to the local computer.

          Zero is right for `core.local`, which opens no connection at all; the
          throttle exists for SSH transports.
        '';
      };
    };

    broker = {
      backend = lib.mkOption {
        type = lib.types.enum [
          "core.zeromq"
          "core.rabbitmq"
          "none"
        ];
        default = "core.zeromq";
        description = ''
          Message broker the daemon uses to control processes.

          `core.zeromq` (the default) needs no external service: the daemon
          starts the broker itself as an extra circus watcher, so a working
          instance needs nothing but PostgreSQL.

          `core.rabbitmq` is the long-established backend and requires a running
          RabbitMQ server — see {option}`services.aiida.broker.createLocally`.

          `none` leaves the profile without a broker. The daemon cannot then run
          at all and `submit()` is unavailable; only `run()` works, in the
          caller's own process. This module refuses to start the daemon unit in
          that case rather than letting it crash-loop.
        '';
      };

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          When {option}`broker.backend` is `core.rabbitmq`, also enable
          {option}`services.rabbitmq` on this machine and order the daemon after
          it. Set to false to point at a RabbitMQ server elsewhere.

          Ignored for the other backends, which need no server.
        '';
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "amqp"
          "amqps"
        ];
        default = "amqp";
        description = "Protocol used to reach RabbitMQ.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "RabbitMQ host.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5672;
        description = "RabbitMQ port.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "guest";
        description = "RabbitMQ username.";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "guest";
        description = ''
          RabbitMQ password.

          This value lands in the Nix store, so use
          {option}`broker.passwordFile` for anything but a single-machine
          deployment using RabbitMQ's default guest account, which only accepts
          connections from loopback anyway.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/credentials/aiida-init.service/broker-password";
        description = ''
          Path to a file containing the RabbitMQ password, read at profile setup
          rather than written into the store. Takes precedence over
          {option}`broker.password`.
        '';
      };

      virtualHost = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "RabbitMQ virtual host. The empty string means the server's default vhost.";
      };
    };

    database = {

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Manage a local PostgreSQL database for AiiDA.

          When true (the default) the module enables {option}`services.postgresql`,
          creates the role and the database, and connects over the local Unix
          socket at {file}`/run/postgresql` using peer authentication, so no
          password is needed.

          Set to false to use a PostgreSQL instance elsewhere, and supply
          {option}`database.host`, {option}`database.port`,
          {option}`database.user` and {option}`database.passwordFile`.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = if cfg.database.createLocally then "/run/postgresql" else "localhost";
        defaultText = lib.literalExpression ''
          if config.services.aiida.database.createLocally
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
        default = "aiida";
        description = "PostgreSQL database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "aiida";
        description = ''
          PostgreSQL role that AiiDA connects as.
          For local peer-authenticated connections this must match
          {option}`services.aiida.user`.
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/credentials/aiida-init.service/db-password";
        description = ''
          Path to a file containing the PostgreSQL password, read when the
          profile is created so that it never appears in the Nix store.

          Not needed for local Unix-socket peer authentication, where the
          password is set to the empty string that the storage backend requires
          to be present but PostgreSQL ignores.

          Note that AiiDA records the password in
          {file}`''${stateDir}/.aiida/config.json`, which it writes with umask
          0077. That is inherent to the `core.psql_dos` backend, not something
          this module chooses.
        '';
      };

      autoMigrate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `verdi storage migrate` automatically before starting the daemon,
          applying any schema migrations a newer aiida-core needs.

          Left false by default for the same reason
          {option}`services.qcfractal.database.autoUpgrade` is: an aiida-core
          upgrade that adds migrations makes the daemon refuse to start, and a
          schema migration on a large provenance graph is not something to
          trigger implicitly from a `nixos-rebuild switch`. With this false the
          migration is a manual step:

          ```
          systemctl start aiida-storage-migrate.service
          ```

          The unit is defined either way; this option only controls whether it
          is pulled in at boot and ordered before {file}`aiida-daemon.service`.
        '';
      };
    };

    configOptions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.bool
          lib.types.int
          lib.types.str
        ]
      );
      default = { };
      example = {
        "warnings.development_version" = false;
        "daemon.timeout" = 30;
      };
      description = ''
        Options applied with `verdi config set` when the profile is created and
        on every later activation.

        These are AiiDA's own configuration options — `verdi config list` shows
        the full set — and are how the instance is tuned; there is no
        module-generated configuration file to override, because AiiDA keeps its
        settings in {file}`config.json` and manages it through the CLI.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = localDB -> (cfg.user == cfg.database.user);
        message = ''
          services.aiida: when database.createLocally is true, database.user
          must match user ("${cfg.user}") because PostgreSQL peer
          authentication maps the OS user name to the role name.
        '';
      }
      {
        assertion = !cfg.database.createLocally -> (cfg.database.host != "/run/postgresql");
        message = ''
          services.aiida: database.host is "/run/postgresql" but
          database.createLocally is false.  Either enable createLocally or set
          database.host to the address of your external PostgreSQL server.
        '';
      }
      {
        assertion =
          localRabbit
          -> builtins.elem cfg.broker.host [
            "127.0.0.1"
            "::1"
            "localhost"
          ];
        message = ''
          services.aiida: broker.createLocally is true, which enables RabbitMQ
          on this machine, but broker.host is "${cfg.broker.host}".  The profile
          would be pointed at a different server than the one being started
          here.  Either set broker.host to localhost or set
          broker.createLocally = false.
        '';
      }
    ];

    warnings = lib.optional (cfg.broker.backend == "none") ''
      services.aiida: broker.backend is "none", so the daemon cannot run and
      aiida-daemon.service will not be started.  Processes can only be executed
      with run() in the caller's own process; submit() is unavailable.
    '';

    users.users = lib.mkIf (cfg.user == "aiida") {
      aiida = {
        isSystemUser = true;
        inherit (cfg) group;
        home = cfg.stateDir;
        description = "AiiDA daemon";
      };
    };

    users.groups = lib.mkIf (cfg.group == "aiida") {
      aiida = { };
    };

    # Both the role *and* the database, unlike ./qcfractal-server.nix which
    # deliberately creates only the role.  The difference is real: qcfractal's
    # `init-db` bootstraps its schema only on the code path where it creates the
    # database itself, so pre-creating it there is fatal.  AiiDA has no such
    # branch — `verdi profile setup core.psql_dos` runs the Alembic migrator
    # against whatever database it is pointed at and creates the schema there,
    # and it does not create the database.
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

    services.rabbitmq = lib.mkIf localRabbit {
      enable = lib.mkDefault true;
    };

    # `verdi` is not only the daemon's launcher: inspecting provenance, exporting
    # archives, adding computers and codes are all things a human does by hand,
    # and all of them need the plugins on the path too.  Installing the same
    # environment the daemon runs is what makes `verdi` on an operator's shell
    # agree with what the daemon sees.
    environment.systemPackages = [ pythonEnv ];

    # AiiDA writes config.json with umask 0077 and expects to own its whole
    # tree; 0700 keeps the profile's database password unreadable to others.
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 '${cfg.user}' '${cfg.group}' - -"
    ]
    ++ lib.optional cfg.setupLocalhost "d '${cfg.localhost.workDir}' 0700 '${cfg.user}' '${cfg.group}' - -";

    systemd.services.aiida-init = {
      description = "AiiDA - create the profile and its storage";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
      ]
      ++ lib.optional localDB "postgresql.target"
      ++ lib.optional localRabbit "rabbitmq.service";
      requires = lib.optional localDB "postgresql.target" ++ lib.optional localRabbit "rabbitmq.service";

      environment.AIIDA_PATH = cfg.stateDir;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        ExecStart = setupScript;
      };
    };

    # Defined unconditionally so it can be run by hand after a backup, which is
    # what an aiida-core upgrade that adds migrations calls for, but only wired
    # into the boot sequence when database.autoMigrate is set.  Same shape as
    # qcfractal-upgrade-db in ./qcfractal-server.nix.
    systemd.services.aiida-storage-migrate = {
      description = "AiiDA - apply storage schema migrations";
      wantedBy = lib.optional cfg.database.autoMigrate "multi-user.target";
      after = [
        "network.target"
        "aiida-init.service"
      ]
      ++ lib.optional localDB "postgresql.target";
      requires = [ "aiida-init.service" ] ++ lib.optional localDB "postgresql.target";

      environment.AIIDA_PATH = cfg.stateDir;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        ExecStart = "${verdi} -p ${cfg.profileName} storage migrate --force";
      };
    };

    systemd.services.aiida-daemon = lib.mkIf (cfg.broker.backend != "none") {
      description = "AiiDA daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "aiida-init.service"
      ]
      ++ lib.optional cfg.database.autoMigrate "aiida-storage-migrate.service"
      ++ lib.optional localDB "postgresql.target"
      ++ lib.optional localRabbit "rabbitmq.service";
      requires = [
        "aiida-init.service"
      ]
      ++ lib.optional cfg.database.autoMigrate "aiida-storage-migrate.service"
      ++ lib.optional localDB "postgresql.target"
      ++ lib.optional localRabbit "rabbitmq.service";

      # The daemon shells out to `verdi` by name for its worker and broker
      # subprocesses, so the environment holding the plugins has to be on PATH,
      # not merely referenced by absolute path in ExecStart.  cfg.extraPackages
      # is here because a core.local calculation is launched by the worker and
      # inherits this PATH.
      path = [ pythonEnv ] ++ cfg.extraPackages;

      environment.AIIDA_PATH = cfg.stateDir;

      # Bound the restart loop.  With RestartSec=15s systemd's default start
      # limit (5 failures in 10s) can never trigger, so a permanently broken
      # configuration would restart forever without ever reaching "failed".
      startLimitIntervalSec = 600;
      startLimitBurst = 10;

      serviceConfig = {
        # `verdi daemon start` launches `verdi daemon start-circus`, which
        # daemonizes and writes the arbiter's pid to circusPidFile, then returns
        # once the daemon answers.  That is exactly Type=forking's contract.
        #
        # Not Type=exec with `daemon start-circus --foreground`: _start_daemon()
        # in aiida/engine/daemon/client.py raises "can only run a single worker
        # when running in the foreground", so that shape could never honour
        # services.aiida.workers.
        Type = "forking";
        PIDFile = circusPidFile;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "15s";

        ExecStart = "${verdi} -p ${cfg.profileName} daemon start ${toString cfg.workers}";
        ExecStop = "${verdi} -p ${cfg.profileName} daemon stop";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.stateDir ] ++ lib.optional cfg.setupLocalhost cfg.localhost.workDir;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
