# tests/aiida/default.nix
#
# Evaluation tests for the AiiDA NixOS module.
#
# Run all tests:
#   nix-build tests -A aiida.all
#
# Run one test:
#   nix-build tests -A aiida.daemon-defaults
#   nix-build tests -A aiida.assertion-user-mismatch
#
# Or directly, bypassing tests/default.nix:
#   nix-build tests/aiida -A daemon-defaults
#
# The harness here is deliberately a copy of ../qcarchive/default.nix rather
# than a shared library: the two suites stub different packages and disagree
# about what a "correct configuration" looks like, and factoring out the four
# helpers would couple them for no gain.

{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs) lib;

  # ---------------------------------------------------------------------------
  # Stub package injected via nixpkgs.overlays — the only safe extension point
  # when using eval-config.nix, which already sets nixpkgs.pkgs internally.
  # ---------------------------------------------------------------------------
  stubOverlay = _final: _prev: {
    aiida-core = pkgs.runCommand "aiida-core-stub" {
      # The module builds a python env from cfg.package.pythonModule to hold
      # aiida-core plus the plugins, and withPackages only accepts packages
      # carrying this attribute.
      passthru.pythonModule = pkgs.python3;
      meta.mainProgram = "verdi";
    } "mkdir -p $out/bin && touch $out/bin/verdi && chmod +x $out/bin/verdi";
  };

  # A stand-in for a plugin package.  It has to look enough like a Python
  # package for withPackages to accept it.
  stubPlugin = pkgs.runCommand "aiida-stub-plugin" {
    passthru.pythonModule = pkgs.python3;
  } "mkdir -p $out";

  # Silence the stateVersion warning that fires on every eval-config.nix call.
  noStateVersionWarning = {
    system.stateVersion = lib.mkDefault "26.11";
  };

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

  evalAiida =
    extraConfig:
    (nixosEval [
      ../../nixos-modules/aiida.nix
      extraConfig
    ]).config;

  # check: boolean expression → pass/fail derivation.  $out must be a directory
  # because symlinkJoin refuses a plain file.
  check =
    name: assertion:
    pkgs.runCommand "test-${name}" { } (
      if assertion then "echo 'PASS: ${name}' && mkdir $out" else "echo 'FAIL: ${name}' >&2 && exit 1"
    );

  assertFails =
    name: evalCall:
    let
      result = builtins.tryEval (builtins.seq evalCall.config.system.build.toplevel true);
    in
    check name (!result.success);

  # Real (unstubbed) package set, for the overlay contract tests below.
  overlaidPkgs = pkgs.extend (import ../../overlays).aiida;

  # Everything the aiida overlay lifts to the top level of pkgs and
  # ../../default.nix re-exports.  Deliberately not derived from either file:
  # the point of the two tests below is that three hand-written lists — this
  # one, the `inherit (final.python313Packages)` in ../../overlays/default.nix
  # and the `inherit (py)` in ../../default.nix — say the same thing.
  #
  # The tier-1 to tier-3 dependencies are absent on purpose.  They stay
  # reachable through python313Packages and are not top-level attributes, so
  # ci.nix does not build them in their own right.
  exportedPackages = [
    "aiida-core"
    "aiida-cp2k"
    "aiida-octopus"
    "aiida-orca"
    "aiida-psi4"
    "aiida-quantumespresso"
  ];

  # aiida-init's ExecStart is a writeShellScript derivation; the daemon's is a
  # plain string.  `.text` rather than builtins.readFile: reading the store path
  # would be import-from-derivation, which builds the script — and the whole
  # point of this suite, and of scripts/no-daemon-check.sh reading the verdicts
  # out of buildCommand, is that nothing gets built.
  initScript = cfg: cfg.systemd.services.aiida-init.serviceConfig.ExecStart.text;
  daemonStart = cfg: cfg.systemd.services.aiida-daemon.serviceConfig.ExecStart;

in
lib.fix (self: {
  # ==========================================================================
  # Overlay contract
  #
  # Everything below stubs pkgs.aiida-core, so it cannot notice if the overlay
  # stops providing it.  These three deliberately bypass the stub.  Evaluation
  # only — nothing is built.
  # ==========================================================================

  # mkPackageOption in the module resolves against the *top level* of pkgs, not
  # python313Packages.  The plugins are aliased for the same reason: a NixOS
  # configuration writes `services.aiida.plugins = [ pkgs.aiida-cp2k ]`.
  aiida-overlay-toplevel-packages = check "aiida-overlay-toplevel-packages" (
    lib.all (
      name: overlaidPkgs ? ${name} && overlaidPkgs.${name} == overlaidPkgs.python313Packages.${name}
    ) exportedPackages
  );

  # The interpreter is spelled out twice — `py` in ../../default.nix and the
  # top-level `inherit` in ../../overlays/default.nix — and nothing forces the
  # two to agree.  If they drift, `nix-build -A aiida-core` and pkgs.aiida-core
  # silently become different derivations and every consumer builds the closure
  # twice.
  aiida-overlay-python-pin = check "aiida-overlay-python-pin" (
    let
      nur = import ../../default.nix { inherit pkgs; };
    in
    lib.all (name: nur ? ${name} && nur.${name} == overlaidPkgs.${name}) exportedPackages
  );

  # The module invokes the package through a withPackages environment, but
  # meta.mainProgram still has to be right: lib.getExe' is used for `verdi`, and
  # anything else reaching for lib.getExe would otherwise land on a
  # $out/bin/aiida-core that does not exist.
  aiida-overlay-main-program = check "aiida-overlay-main-program" (
    lib.hasSuffix "/bin/verdi" (lib.getExe overlaidPkgs.aiida-core)
  );

  # The overlay must not disturb the QCArchive family, which shares the
  # interpreter: the pymatgen override lives at aiida-core's callPackage site
  # precisely so that it cannot leak into python313Packages generally.
  aiida-overlay-pymatgen-override-is-local = check "aiida-overlay-pymatgen-override-is-local" (
    !(builtins.tryEval overlaidPkgs.python313Packages.pymatgen.drvPath).success
  );

  # ==========================================================================
  # Module — correct configurations
  # ==========================================================================

  # Disabled: no services should be created.
  aiida-disabled = check "aiida-disabled" (
    let
      cfg = evalAiida { };
    in
    !(cfg.systemd.services ? aiida-init) && !(cfg.systemd.services ? aiida-daemon)
  );

  aiida-defaults = check "aiida-defaults" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
    in
    cfg.systemd.services ? aiida-init
    && cfg.systemd.services ? aiida-daemon
    && cfg.systemd.services ? aiida-storage-migrate
    && cfg.services.postgresql.enable
  );

  # Unlike qcfractal, the database *is* pre-created here: `verdi profile setup
  # core.psql_dos` runs the Alembic migrator against a database it expects to
  # already exist, and never creates one.  The inverse test in
  # ../qcarchive/default.nix (server-db-not-precreated) is not a contradiction —
  # the two tools bootstrap differently, and getting either backwards leaves a
  # service that cannot start.
  aiida-postgres-creates-database = check "aiida-postgres-creates-database" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
    in
    cfg.services.postgresql.ensureDatabases == [ "aiida" ]
    && (
      let
        users = cfg.services.postgresql.ensureUsers;
      in
      builtins.length users == 1
      && (builtins.head users).name == "aiida"
      && (builtins.head users).ensureDBOwnership
    )
  );

  # createLocally = false: postgresql must not be touched.
  aiida-postgres-remote = check "aiida-postgres-remote" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          database.createLocally = false;
          database.host = "db.example.com";
        };
      };
    in
    !cfg.services.postgresql.enable
  );

  # AIIDA_PATH is what puts the configuration directory, the file repository and
  # the daemon's runtime files under stateDir instead of the service user's
  # home.  Every unit needs it, not just the daemon.
  aiida-path-on-every-unit = check "aiida-path-on-every-unit" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          stateDir = "/srv/aiida";
        };
      };
      unitPath = unit: cfg.systemd.services.${unit}.environment.AIIDA_PATH or null;
    in
    unitPath "aiida-init" == "/srv/aiida"
    && unitPath "aiida-storage-migrate" == "/srv/aiida"
    && unitPath "aiida-daemon" == "/srv/aiida"
    && cfg.systemd.services.aiida-daemon.serviceConfig.WorkingDirectory == "/srv/aiida"
  );

  # systemd has to be able to find the circus arbiter under Type=forking, and
  # the path AiiDA writes it to embeds the profile name.  Getting this wrong
  # makes the unit time out on start even though the daemon is running.
  aiida-pidfile-matches-profile = check "aiida-pidfile-matches-profile" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          stateDir = "/srv/aiida";
          profileName = "research";
        };
      };
      sc = cfg.systemd.services.aiida-daemon.serviceConfig;
    in
    sc.Type == "forking" && sc.PIDFile == "/srv/aiida/.aiida/daemon/circus-research.pid"
  );

  # The worker count must reach `verdi daemon start`, and ExecStop must exist:
  # without it systemd would SIGTERM the arbiter and leave the pid file behind,
  # which AiiDA then reports as a stale daemon.
  aiida-workers-and-stop = check "aiida-workers-and-stop" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          workers = 4;
        };
      };
      sc = cfg.systemd.services.aiida-daemon.serviceConfig;
    in
    lib.hasInfix "daemon start 4" sc.ExecStart && lib.hasInfix "daemon stop" sc.ExecStop
  );

  # ==========================================================================
  # Plugins
  #
  # The regression guard for the whole point of this module: the daemon spawns
  # `verdi daemon worker` as a *subprocess*, which re-resolves verdi from PATH.
  # A plugin that is not in the environment that PATH points at is invisible,
  # and the failure surfaces as an unknown entry point on a submitted
  # calculation rather than anywhere near here.
  # ==========================================================================

  aiida-plugins-reach-path = check "aiida-plugins-reach-path" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          plugins = [ stubPlugin ];
        };
      };
      unit = cfg.systemd.services.aiida-daemon;
      # The env is a withPackages result, so it is neither cfg.package nor the
      # plugin itself; what matters is that a single derivation on PATH has both
      # in its closure.
      env = builtins.head unit.path;
    in
    lib.hasInfix "-env" env.name && builtins.elem stubPlugin env.paths
  );

  # ExecStart must point *into* that same environment rather than at the bare
  # package, or the daemon and its workers disagree about what is installed.
  aiida-verdi-comes-from-env = check "aiida-verdi-comes-from-env" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          plugins = [ stubPlugin ];
        };
      };
      env = builtins.head cfg.systemd.services.aiida-daemon.path;
    in
    lib.hasPrefix "${env}/bin/verdi" (daemonStart cfg)
  );

  # Simulation codes are a different axis from plugins: the plugin is a Python
  # package, the code is an executable the worker launches.  Both end up on the
  # unit's PATH, and neither should displace the other.
  aiida-extra-packages-on-path = check "aiida-extra-packages-on-path" (
    let
      fakeCode = pkgs.runCommand "pw-stub" { } "mkdir -p $out/bin && touch $out/bin/pw.x";
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          plugins = [ stubPlugin ];
          extraPackages = [ fakeCode ];
        };
      };
      unit = cfg.systemd.services.aiida-daemon;
    in
    builtins.elem fakeCode unit.path
    # The python environment must come first.  systemd appends its own default
    # entries (coreutils, findutils, gnugrep, gnused, systemd) to every unit's
    # path, and a simulation code package is free to ship whatever it likes in
    # bin/ — so the ordering is what guarantees that the `verdi` a worker
    # subprocess resolves is the one holding the plugins.
    && lib.hasInfix "-env" (builtins.head unit.path).name
  );

  # ==========================================================================
  # Broker
  # ==========================================================================

  # ZeroMQ is the default and needs no service at all — that is the whole reason
  # it is the default.
  aiida-broker-zeromq-default = check "aiida-broker-zeromq-default" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
    in
    lib.hasInfix "--broker 'core.zeromq'" (initScript cfg) && !cfg.services.rabbitmq.enable
  );

  aiida-broker-rabbitmq-enables-service = check "aiida-broker-rabbitmq-enables-service" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          broker.backend = "core.rabbitmq";
        };
      };
    in
    cfg.services.rabbitmq.enable
    && builtins.elem "rabbitmq.service" cfg.systemd.services.aiida-daemon.requires
  );

  # `profile setup --broker core.rabbitmq` calls detect_rabbitmq_config(), which
  # probes localhost and silently produces a broker-less profile when the probe
  # fails.  The module must follow up with configure-broker so the connection
  # parameters are the ones that were declared.
  aiida-broker-rabbitmq-pins-parameters = check "aiida-broker-rabbitmq-pins-parameters" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          broker = {
            backend = "core.rabbitmq";
            createLocally = false;
            host = "mq.example.com";
            port = 5673;
            virtualHost = "aiida";
          };
        };
      };
      s = initScript cfg;
    in
    lib.hasInfix "profile configure-broker core.rabbitmq" s
    && lib.hasInfix "--broker-host 'mq.example.com'" s
    && lib.hasInfix "--broker-port '5673'" s
    && lib.hasInfix "--broker-virtual-host 'aiida'" s
  );

  # broker.backend = "none" is a legitimate configuration — it is what upstream
  # calls a broker-less profile — but the daemon genuinely cannot run, so
  # defining the unit would produce a guaranteed crash loop.
  aiida-broker-none-has-no-daemon = check "aiida-broker-none-has-no-daemon" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          broker.backend = "none";
        };
      };
    in
    !(cfg.systemd.services ? aiida-daemon) && cfg.warnings != [ ]
  );

  # ==========================================================================
  # Secrets
  # ==========================================================================

  # Both passwords are read from their files at run time.  The store is world
  # readable, so a password that reaches ExecStart as a literal is a password
  # every user on the machine can read.
  aiida-passwords-not-in-store = check "aiida-passwords-not-in-store" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          database.createLocally = false;
          database.host = "db.example.com";
          database.passwordFile = "/run/secrets/aiida-db";
          broker.backend = "core.rabbitmq";
          broker.createLocally = false;
          broker.passwordFile = "/run/secrets/aiida-broker";
        };
      };
      s = initScript cfg;
    in
    lib.hasInfix ''AIIDA_DB_PASSWORD="$(< '/run/secrets/aiida-db')"'' s
    && lib.hasInfix ''AIIDA_BROKER_PASSWORD="$(< '/run/secrets/aiida-broker')"'' s
  );

  # ==========================================================================
  # Storage migration
  # ==========================================================================

  # The migration unit always exists so it can be run by hand after a backup,
  # but by default nothing pulls it in and the daemon does not wait on it.
  aiida-migrate-manual-by-default = check "aiida-migrate-manual-by-default" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
      migrate = cfg.systemd.services.aiida-storage-migrate;
    in
    migrate.wantedBy == [ ]
    && !(builtins.elem "aiida-storage-migrate.service" cfg.systemd.services.aiida-daemon.requires)
    # It must still be ordered after aiida-init, so a manual run on a fresh
    # machine cannot race the profile creation it depends on.
    && builtins.elem "aiida-init.service" migrate.requires
  );

  aiida-migrate-auto = check "aiida-migrate-auto" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          database.autoMigrate = true;
        };
      };
      migrate = cfg.systemd.services.aiida-storage-migrate;
      daemon = cfg.systemd.services.aiida-daemon;
    in
    migrate.wantedBy == [ "multi-user.target" ]
    && builtins.elem "aiida-storage-migrate.service" daemon.requires
    && builtins.elem "aiida-storage-migrate.service" daemon.after
  );

  # ==========================================================================
  # Setup script
  # ==========================================================================

  # Creating the profile must be idempotent: aiida-init is RemainAfterExit, but
  # it re-runs on every boot after a restart, and `verdi profile setup` on an
  # existing profile is a hard error.
  aiida-init-is-idempotent = check "aiida-init-is-idempotent" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
      s = initScript cfg;
    in
    lib.hasInfix "if ! " s
    && lib.hasInfix "profile show 'main'" s
    && cfg.systemd.services.aiida-init.serviceConfig.RemainAfterExit
  );

  aiida-localhost-configured = check "aiida-localhost-configured" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          stateDir = "/srv/aiida";
        };
      };
      s = initScript cfg;
    in
    lib.hasInfix "computer setup" s
    && lib.hasInfix "--transport core.local" s
    && lib.hasInfix "--scheduler core.direct" s
    && lib.hasInfix "--work-dir '/srv/aiida/scratch'" s
    # The scratch directory has to exist and be writable before a calculation
    # lands in it, and ProtectSystem=strict means it also has to be declared.
    && builtins.elem "/srv/aiida/scratch" cfg.systemd.services.aiida-daemon.serviceConfig.ReadWritePaths
  );

  aiida-localhost-disabled = check "aiida-localhost-disabled" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          setupLocalhost = false;
        };
      };
    in
    !(lib.hasInfix "computer setup" (initScript cfg))
  );

  # configOptions is the only knob AiiDA offers for its own settings — there is
  # no module-generated config file, because config.json is CLI-managed — so
  # booleans have to be rendered the way `verdi config set` parses them, not the
  # way Nix prints them.
  aiida-config-options = check "aiida-config-options" (
    let
      cfg = evalAiida {
        services.aiida = {
          enable = true;
          configOptions = {
            "warnings.development_version" = false;
            "daemon.timeout" = 30;
          };
        };
      };
      s = initScript cfg;
    in
    # Unquoted because lib.escapeShellArg only quotes when a string actually
    # needs it, and neither of these does.  What is being checked is the
    # rendering of the *value*: `false` must reach the CLI as Python's `False`,
    # not as Nix's `false`, which AiiDA's option parser rejects.
    lib.hasInfix "config set warnings.development_version False" s
    && lib.hasInfix "config set daemon.timeout 30" s
  );

  aiida-user-created = check "aiida-user-created" (
    let
      cfg = evalAiida { services.aiida.enable = true; };
    in
    cfg.users.users ? aiida && cfg.users.users.aiida.isSystemUser && cfg.users.groups ? aiida
  );

  # ==========================================================================
  # Assertion violations (must throw during evaluation)
  # ==========================================================================

  aiida-assertion-user-mismatch = assertFails "aiida-assertion-user-mismatch" (nixosEval [
    ../../nixos-modules/aiida.nix
    {
      services.aiida = {
        enable = true;
        user = "aiida";
        database.createLocally = true;
        database.user = "different-user";
      };
    }
  ]);

  aiida-assertion-socket-without-local =
    assertFails "aiida-assertion-socket-without-local"
      (nixosEval [
        ../../nixos-modules/aiida.nix
        {
          services.aiida = {
            enable = true;
            database.createLocally = false;
            database.host = "/run/postgresql";
          };
        }
      ]);

  # Enabling a local RabbitMQ while pointing the profile at a remote one is the
  # sort of configuration that comes up healthy and cannot submit anything.
  aiida-assertion-rabbitmq-host-mismatch =
    assertFails "aiida-assertion-rabbitmq-host-mismatch"
      (nixosEval [
        ../../nixos-modules/aiida.nix
        {
          services.aiida = {
            enable = true;
            broker.backend = "core.rabbitmq";
            broker.createLocally = true;
            broker.host = "mq.example.com";
          };
        }
      ]);

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "aiida-module-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
