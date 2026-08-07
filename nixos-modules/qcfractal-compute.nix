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
        inherit (cfg.server) username;
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

  py = cfg.package.pythonModule;

  # A single merged site-packages directory holding qcfractalcompute and its
  # whole dependency closure, exported as PYTHONPATH on the unit below so that
  # QCEngine's out-of-process program discovery can import qcengine.
  pythonEnv = py.withPackages (_: [ cfg.package ]);

  # QC programs written in Python need their own dependency closure importable
  # as well — see the PYTHONPATH comment below.  They come in two shapes, and
  # only one of them can name its own interpreter:
  #
  #   * a module (buildPythonPackage): `pythonModule` is the interpreter, and
  #     the package itself is what belongs in the env;
  #   * an application (toPythonApplication): `pythonModule` is deliberately
  #     `false`, so that nothing treats the program as importable.  This is
  #     what pkgs.qchem.psi4 is — NixOS-QChem's overlay.nix builds it as
  #     `toPythonApplication python3.pkgs.psi4`.  Its dependency closure is
  #     `requiredPythonModules`, which carries the interpreter along as its one
  #     non-module element.
  #
  # Testing `pythonModule` for a *derivation* rather than for presence is the
  # whole point: the application form has the attribute, set to `false`, so a
  # `p ? pythonModule` check passes and then finds no pythonVersion behind it.
  # Anything else — a plain executable such as pkgs.qchem.cfour — contributes
  # no modules and is skipped, as is a program built for another interpreter,
  # whose site-packages would not even sit at the same path.
  #
  # psi4 itself is deliberately not added: QCEngine's `psi4 --module` fallback
  # already puts it on sys.path, and the application form has no business in a
  # python env.  Only its dependencies were ever missing.
  programPythonEnv =
    p:
    let
      isModule = lib.isDerivation (p.pythonModule or false);
      mods = if isModule then [ p ] else p.requiredPythonModules or [ ];
      interp =
        if isModule then
          p.pythonModule
        else
          lib.findFirst (m: m ? pythonVersion && m ? withPackages) null mods;
    in
    if interp == null || interp.pythonVersion != py.pythonVersion then
      null
    else
      interp.withPackages (_: mods);

  # Each program gets its own env instead of being merged into pythonEnv,
  # because pkgs.qchem.* is instantiated from a *different* nixpkgs than this
  # module's pkgs (see flake.nix on nixpkgs-qchem).  Merging would collide on
  # every package the two closures share — numpy, pydantic, qcelemental,
  # qcengine — at differing versions.  Appending instead leaves those resolving
  # to pythonEnv, exactly as they do today via QCEngine's `psi4 --module`
  # sys.path fallback; only the program's private dependencies come from here.
  programEnvs = lib.remove null (map programPythonEnv cfg.executor.programs);

  pythonPath = lib.concatMapStringsSep ":" (e: "${e}/${py.sitePackages}") (
    [ pythonEnv ] ++ programEnvs
  );

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
        inherit (cfg) group;
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

      environment = {
        # Required for any program to be discovered at all.
        #
        # Discovery does not run in-process: AppManager.discover_programs_conda
        # shells out with
        #
        #   subprocess.check_output(["python3", <qcengine_list.py>])
        #
        # and nixpkgs injects a package's dependencies with site.addsitedir()
        # *inside* the wrapped script, which does not carry into a child
        # process.  The child is therefore a bare interpreter that cannot
        # import qcengine, and qcengine_list.py turns that into silence:
        #
        #   except ImportError:
        #       progs = {}
        #       procs = {}
        #
        # so discovery yields zero programs and the manager exits with
        # "Executor <label> has no available programs" no matter what
        # executor.programs contains — a message that points at the wrong
        # thing entirely.
        #
        # PATH cannot fix this: the wrapper around qcfractal-compute-manager
        # prepends its own bare interpreter, which would win over anything
        # placed here.  NIX_PYTHONPATH cannot either — sitecustomize.py pops it
        # ("unset in order to prevent leakage"), so children never see it.
        # PYTHONPATH is inherited, and pythonEnv merges the whole closure into
        # one directory, so one entry covers discovery.
        #
        # The trailing entries, one per Python-package program, are needed for
        # a second and unrelated reason: a Python-native harness may import its
        # program *in-process* even when the calculation itself runs as a
        # subprocess.  QCEngine 0.50.0 made Psi4Harness.compute do exactly that
        #
        #   psi4_can_v2 = "dtype" in inspect.signature(
        #       psi4.driver.p4util.state_to_atomicinput).parameters
        #
        # replacing the plain version comparison 0.50.0rc2 used.  Psi4Harness
        # .found() puts psi4 itself on sys.path (it runs `psi4 --module` and
        # appends the printed path), but that directory alone carries none of
        # psi4's dependencies, so `import psi4` reaches driver_nbody.py and
        # dies with "No module named 'qcmanybody'".  QCEngine catches it as an
        # execution error, so the manager stays up and every task it claims
        # errors instead — the failure looks like a bad calculation, not a
        # missing module.
        #
        # Verified by running qcengine_list.py directly: bare gives "{}",
        # with this set it gives {"psi4": "1.10", "qcengine": "..."}.  A full
        # HF/STO-3G calculation also runs correctly with it set, returning
        # -1.1167383 Eh, so the variable leaking into the QC program's own
        # subprocess is harmless.
        PYTHONPATH = pythonPath;
      };

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
