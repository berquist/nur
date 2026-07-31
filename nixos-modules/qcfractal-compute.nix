# nixos-modules/qcfractal-compute.nix
#
# NixOS module for the QCFractalCompute local worker.
# Import this file directly, or reference it as
#   inputs.nur.nixosModules.qcfractal-compute
# from your system flake.
#
# This module is intentionally independent of the server module.
# The worker can connect to a server on the same machine or a remote one.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.qcfractalCompute;

  # Generate the manager config YAML.
  # The server password is intentionally absent; it is injected at runtime
  # via an environment variable read from server.passwordFile.
  computeConfig = lib.generators.toYAML { } (
    {
      cluster = cfg.clusterName;
      loglevel = cfg.logLevel;
      update_frequency = cfg.updateFrequency;

      server = {
        fractal_uri = cfg.server.fractalUri;
      }
      // lib.optionalAttrs (cfg.server.username != null) {
        username = cfg.server.username;
      };

      executors.local_executor = {
        type = "local";
        max_workers = cfg.executor.maxWorkers;
        cores_per_worker = cfg.executor.coresPerWorker;
        memory_per_worker = cfg.executor.memoryPerWorker;
        compute_tags = cfg.executor.computeTags;
        environments.use_manager_environment = true;
      }
      // lib.optionalAttrs (cfg.executor.scratchDirectory != null) {
        scratch_directory = cfg.executor.scratchDirectory;
      };
    }
    // lib.optionalAttrs (cfg.logFile != null) { logfile = cfg.logFile; }
    // cfg.extraConfig
  );

  computeConfigFile = pkgs.writeText "qcf_compute_config.yaml" computeConfig;

in
{
  options.services.qcfractalCompute = {

    enable = lib.mkEnableOption "the QCFractalCompute local worker";

    package = lib.mkPackageOption pkgs "qcfractalcompute" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "qcfractalcompute";
      description = "System user that runs the compute manager.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "qcfractalcompute";
      description = "System group for the compute manager service.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/qcfractalcompute";
      description = "Working directory for the compute manager (Parsl run directory, logs, etc.).";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "nixos-local";
      description = "Descriptive name presented to the QCFractal server.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "DEBUG"
        "INFO"
        "WARNING"
        "ERROR"
      ];
      default = "INFO";
      description = "Logging verbosity.";
    };

    logFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/log/qcfractalcompute/manager.log";
      description = "Log file path. null means log only to the systemd journal.";
    };

    updateFrequency = lib.mkOption {
      type = lib.types.number;
      default = 60.0;
      description = "Seconds between heartbeat / task-claim cycles to the server.";
    };

    server = {
      fractalUri = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:7777";
        example = "https://qcfractal.example.org";
        description = "URI of the QCFractal server to pull tasks from.";
      };

      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          QCFractal username for this compute worker account.
          null attempts unauthenticated access (requires
          {option}`services.qcfractal.allowUnauthenticatedRead` on the server).
        '';
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/credentials/qcfractalcompute.service/server-password";
        description = ''
          Path to a file containing the QCFractal password for
          {option}`server.username`.
          Read at service start; supplied via the
          QCF_COMPUTE_SERVER__PASSWORD environment variable, which
          pydantic-settings maps to the server.password config field.
        '';
      };
    };

    executor = {

      maxWorkers = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = ''
          Maximum number of concurrent worker processes.
          Each worker handles one QCEngine task at a time.
        '';
      };

      coresPerWorker = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "CPU cores allocated per worker process (passed to QCEngine as ncores).";
      };

      memoryPerWorker = lib.mkOption {
        type = lib.types.number;
        default = 4.0;
        description = "Memory allocated per worker process in GiB (passed to QCEngine as memory).";
      };

      scratchDirectory = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/scratch/qcfractal";
        description = ''
          Scratch directory for temporary files written by QCEngine and the
          QC programs.  null uses each program's own default (often /tmp).
          A fast local filesystem (SSD, tmpfs) is strongly recommended.
        '';
      };

      computeTags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "*" ];
        description = ''
          Task tags this worker accepts.
          The wildcard "*" accepts all tags.
          Use named tags to route specific calculation types to specific
          workers (e.g. "gpu" for GPU-accelerated codes).
        '';
      };

      programs = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "with pkgs.qchem; [ psi4 cfour nwchem ]";
        description = ''
          QC program packages to add to the worker service's PATH.

          QCEngine probes PATH at startup to discover which programs are
          available and advertises those capabilities to the server.
          Listing a package here is therefore sufficient — no conda
          environments or worker_init scripts are needed under NixOS.

          Programs available from NixOS-QChem (pkgs.qchem.*) include:
          psi4, cfour, nwchem, orca, gamess-us, xtb, mrcc, and many others.
          pkgs.nwchem is also available directly from nixpkgs.
        '';
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra key-value pairs merged into the generated manager config YAML.
        Values here override module-derived settings.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    users.users = lib.mkIf (cfg.user == "qcfractalcompute") {
      qcfractalcompute = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        description = "QCFractalCompute worker daemon";
      };
    };

    users.groups = lib.mkIf (cfg.group == "qcfractalcompute") {
      qcfractalcompute = { };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 '${cfg.user}' '${cfg.group}' - -"
    ]
    ++ lib.optional (
      cfg.logFile != null
    ) "d '${dirOf cfg.logFile}' 0750 '${cfg.user}' '${cfg.group}' - -"
    ++ lib.optional (
      cfg.executor.scratchDirectory != null
    ) "d '${cfg.executor.scratchDirectory}' 0750 '${cfg.user}' '${cfg.group}' - -";

    systemd.services.qcfractalcompute = {
      description = "QCFractalCompute local worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # QCEngine probes PATH at startup to find available QC programs.
      path = cfg.executor.programs;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "30s";

        ExecStart = pkgs.writeShellScript "qcfractalcompute-start" ''
          set -euo pipefail
          CFG='${cfg.stateDir}/qcf_compute_config.yaml'
          # Update the on-disk config whenever the Nix-generated version changes.
          if ! diff -q '${computeConfigFile}' "$CFG" > /dev/null 2>&1; then
            install -m 0640 '${computeConfigFile}' "$CFG"
          fi
          ${lib.optionalString (cfg.server.passwordFile != null) ''
            # pydantic-settings maps QCF_COMPUTE_SERVER__PASSWORD to
            # the server.password field in FractalComputeConfig.
            export QCF_COMPUTE_SERVER__PASSWORD="$(< '${cfg.server.passwordFile}')"
          ''}
          exec ${lib.getExe cfg.package} --config "$CFG"
        '';

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.stateDir
        ]
        ++ lib.optional (cfg.logFile != null) (dirOf cfg.logFile)
        ++ lib.optional (cfg.executor.scratchDirectory != null) cfg.executor.scratchDirectory;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
