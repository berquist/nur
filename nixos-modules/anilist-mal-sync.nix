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
# The one thing this module cannot do for you: authenticating with each
# service is an interactive OAuth2 flow (a local HTTP server on oauthPort
# that a browser must hit). But it does not need a separate step first --
# `watch` (what the service below runs) calls the same OAuth constructors as
# `login` itself, just with initWithToken=true (see NewApp in upstream's
# app.go), so a fresh systemd unit with no token yet prints
# "Open the following URL in your browser: ..." straight to its own stdout
# -- i.e. `journalctl -u anilist-mal-sync -f` -- and blocks there (once for
# MyAnimeList, then once for AniList) until that URL is opened and the
# consent screen is completed. Tunnel oauthPort to wherever you'll run a
# browser (`ssh -L <oauthPort>:localhost:<oauthPort> <this host>`) *before*
# the unit starts, watch the journal for the two URLs, and the first `--once`
# sync runs right after the second one completes.
#
# anilist-mal-sync-login below exists for the *second* time you need this:
# forcing a fresh login for one service without waiting for the running
# service to notice an expired or revoked token. It needs the service
# stopped first, since both would otherwise fight over oauthPort.
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

      echo 'Not needed for first-time setup -- anilist-mal-sync.service does' >&2
      echo 'this itself on its first start; watch its journal instead:' >&2
      echo '  journalctl -u anilist-mal-sync -f' >&2
      echo 'Use this only to force a fresh login without waiting for the' >&2
      echo 'running service to notice a stale token.' >&2
      echo >&2
      echo "Stop anilist-mal-sync.service first -- the OAuth callback needs" >&2
      echo "port ${toString cfg.oauthPort} free, and the service is likely" >&2
      echo "already holding it." >&2
      echo 'If this host is remote, open a tunnel from wherever the browser' >&2
      echo 'will run first:' >&2
      echo "  ssh -L ${toString cfg.oauthPort}:localhost:${toString cfg.oauthPort} <this host>" >&2
      echo 'then open the URL printed below there.' >&2
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
        # MAL has no built-in request pacing on the update calls this makes
        # (unlike AniList favorites and Jikan, which do), so a large first
        # sync can get some requests redirected to a page that hangs rather
        # than erroring. Lower from the 30s default so those fail fast
        # instead of eating up to 30s per retry -- it does not stop MAL from
        # rate limiting, just shortens how long a bad run takes.
        HTTP_TIMEOUT = "10s";
      };
      description = ''
        Non-secret environment variables passed to the service, e.g.
        ANILIST_USERNAME, MAL_USERNAME, WATCH_INTERVAL or WATCH_SCHEDULE
        (mutually exclusive), and the various *_API_ENABLED / *_CACHE_DIR
        toggles. See upstream's config.example.yaml and .env.example for the
        full list -- every setting there has an environment-variable form.
      '';
    };

    syncTarget = lib.mkOption {
      type = lib.types.enum [
        "anime"
        "manga"
        "all"
      ];
      default = "anime";
      description = ''
        Which lists `watch` syncs, matching the CLI's --manga/--all flags
        (there is no environment-variable form of these, so this option
        appends the flag rather than going through {option}`environment`):
        "anime" (upstream's own default -- anime only), "manga" (manga
        only, upstream's --manga), or "all" (both, upstream's --all).
      '';
    };

    reverseDirection = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Sync from MyAnimeList to AniList instead of the default AniList to
        MyAnimeList -- upstream's --reverse-direction flag, which likewise
        has no environment-variable form.
      '';
    };

    oauthPort = lib.mkOption {
      type = lib.types.port;
      default = 18080;
      description = ''
        Port the OAuth callback briefly listens on. Reached not just by
        anilist-mal-sync-login but by the service itself: `watch` opens this
        same listener the first time it runs with no token yet (or whenever
        one has expired or been revoked), and blocks until the browser
        round-trip against it completes -- see the note at the top of this
        file.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`services.anilist-mal-sync.oauthPort` in the firewall.

        Left false by default: the intended way to reach it, whether the
        service is doing its own first-run login or anilist-mal-sync-login
        is forcing a fresh one, is an SSH tunnel
        (`ssh -L <port>:localhost:<port>`) from wherever the browser runs,
        not a public listener.
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

        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe cfg.package)
            "watch"
            "--once"
          ]
          ++ lib.optional (cfg.syncTarget == "manga") "--manga"
          ++ lib.optional (cfg.syncTarget == "all") "--all"
          ++ lib.optional cfg.reverseDirection "--reverse-direction"
        );

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
