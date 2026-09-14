# nixos-modules/anilist-mal-sync.nix
#
# NixOS module for anilist-mal-sync — a personal background sync of anime and
# manga watch progress between AniList and MyAnimeList.
#
# Unlike qcfractal-server.nix this needs no database and no generated
# secrets, so it is much smaller: the binary reads its whole configuration
# from environment variables (see ../pkgs/anilist-mal-sync and
# config.example.yaml/.env.example in the upstream repo), and every default
# file path it writes (token.json, mappings.yaml, and three API caches) comes
# from `os.UserConfigDir()` — i.e. $XDG_CONFIG_HOME — so pointing that at
# stateDir is enough to keep everything persistent with no path options to
# thread through by hand.
#
# The one thing this module cannot do for you: `login` is an interactive
# OAuth2 flow (a local HTTP server on oauthPort that a browser must hit), and
# only after it succeeds does `watch` run headless against the token it
# writes. See the anilist-mal-sync-login script below.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.anilist-mal-sync;

  # Same privilege-check shape as qcfractal-manage in ./qcfractal-server.nix:
  # help/version answered before any privilege check, then re-exec as cfg.user
  # under root, refuse otherwise.
  loginScript = pkgs.writeShellApplication {
    name = "anilist-mal-sync-login";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      for arg in "$@"; do
        case "$arg" in
          -h | --help | --version)
            exec ${lib.getExe cfg.package} "$@"
            ;;
        esac
      done

      if [ "$(id -u -n)" != '${cfg.user}' ]; then
        if [ "$(id -u)" -ne 0 ]; then
          echo "anilist-mal-sync-login: run as root or as ${cfg.user}." >&2
          exit 1
        fi
        exec runuser -u '${cfg.user}' -- "$0" "$@"
      fi

      export XDG_CONFIG_HOME='${cfg.stateDir}'
      ${lib.optionalString (cfg.environmentFile != null) ''
        set -a
        # shellcheck source=/dev/null
        . '${cfg.environmentFile}'
        set +a
      ''}

      echo 'Stop anilist-mal-sync.service first if it is running -- the OAuth' >&2
      echo "callback needs port ${toString cfg.oauthPort} free." >&2
      echo 'If this host is remote, open a tunnel from your workstation first:' >&2
      echo "  ssh -L ${toString cfg.oauthPort}:localhost:${toString cfg.oauthPort} <this host>" >&2
      echo 'then open the URL printed below in a browser there.' >&2
      echo >&2

      exec ${lib.getExe cfg.package} login "$@"
    '';
  };
in
{
  options.services.anilist-mal-sync = {

    enable = lib.mkEnableOption "the anilist-mal-sync AniList/MyAnimeList sync daemon";

    package = lib.mkPackageOption pkgs "anilist-mal-sync" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "anilist-mal-sync";
      description = "System user that runs anilist-mal-sync.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "anilist-mal-sync";
      description = "System group for the anilist-mal-sync service.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/anilist-mal-sync";
      description = ''
        Directory that holds persistent state: the OAuth token, manual ID
        mappings, and the offline-database/Hato/Jikan caches.

        Exposed to the service as $XDG_CONFIG_HOME, so these all land under
        {file}`''${stateDir}/anilist-mal-sync/` -- see `os.UserConfigDir()`
        in upstream's config.go.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/anilist-mal-sync-credentials";
      description = ''
        Path to a systemd EnvironmentFile holding the OAuth secrets:
        ANILIST_CLIENT_ID, ANILIST_CLIENT_SECRET, MAL_CLIENT_ID and
        MAL_CLIENT_SECRET. Read at service start, so these never appear in
        the Nix store -- typically wired to a sops-nix secret at the host
        level, the same idiom as {option}`security.acme.certs.<name>.environmentFile`.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ANILIST_USERNAME = "myusername";
        MAL_USERNAME = "myusername";
        WATCH_INTERVAL = "24h";
      };
      description = ''
        Non-secret environment variables passed to the service, e.g.
        ANILIST_USERNAME, MAL_USERNAME, WATCH_INTERVAL or WATCH_SCHEDULE
        (mutually exclusive), and the various *_API_ENABLED / *_CACHE_DIR
        toggles. See upstream's config.example.yaml and .env.example for the
        full list -- every setting there has an environment-variable form.
      '';
    };

    oauthPort = lib.mkOption {
      type = lib.types.port;
      default = 18080;
      description = ''
        Port the interactive `login` command briefly listens on for the
        OAuth callback. The long-running `watch` daemon never listens on
        this -- it is only used by anilist-mal-sync-login.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`services.anilist-mal-sync.oauthPort` in the firewall.

        Left false by default: the intended way to reach it during `login`
        is an SSH tunnel (`ssh -L <port>:localhost:<port>`) from the
        workstation doing the browser round-trip, not a public listener.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = (cfg.environment ? WATCH_INTERVAL) || (cfg.environment ? WATCH_SCHEDULE);
        message = ''
          services.anilist-mal-sync: set environment.WATCH_INTERVAL (e.g.
          "24h") or environment.WATCH_SCHEDULE (a 5-field cron expression) --
          `watch` refuses to start with neither.
        '';
      }
    ];

    users.users = lib.mkIf (cfg.user == "anilist-mal-sync") {
      anilist-mal-sync = {
        isSystemUser = true;
        inherit (cfg) group;
        home = cfg.stateDir;
        description = "anilist-mal-sync sync daemon";
      };
    };

    users.groups = lib.mkIf (cfg.group == "anilist-mal-sync") {
      anilist-mal-sync = { };
    };

    environment.systemPackages = [ loginScript ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.oauthPort ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 '${cfg.user}' '${cfg.group}' - -"
    ];

    systemd.services.anilist-mal-sync = {
      description = "anilist-mal-sync -- AniList/MyAnimeList watch-progress sync";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Bound the restart loop, same reasoning as qcfractal.service in
      # ./qcfractal-server.nix: systemd's default start limit (5 failures in
      # 10s) can never trigger with RestartSec=15s, so a permanently broken
      # configuration -- missing credentials, say -- would otherwise restart
      # every 15 seconds forever instead of reaching "failed".
      startLimitIntervalSec = 600;
      startLimitBurst = 10;

      environment = {
        XDG_CONFIG_HOME = cfg.stateDir;
      }
      // cfg.environment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "15s";

        ExecStart = "${lib.getExe cfg.package} watch --once";

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.stateDir ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
