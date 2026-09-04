# home-modules/hydrus-client.nix
#
# home-manager module for reaching a Hydrus GUI that runs on another machine.
# Import this file directly, or reference it as
#   inputs.nur.homeModules.hydrus-client
# from your home-manager flake.
#
# Hydrus has no client/server split of the usual kind: hydrus-client *is* the
# database, and the hydrus-server binary the same package installs is a
# tag/file *repository* that separate full clients synchronise from, each
# keeping its own client.db and its own copy of the files.  So one shared
# library means one client, running headless on the machine that holds it
# inside an xpra session, and this module is the other end of that -- xpra plus
# a wrapper that attaches to the session.  The host side is
# services.hydrus.client from github:hydrui/hydrus-nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.hydrus-client;

  attachArgs = [
    "tcp://${cfg.host}:${toString cfg.port}/"
  ]
  ++ lib.optional (cfg.passwordFile != null) "--password-file=${cfg.passwordFile}"
  ++ cfg.extraAttachArgs;

  # writeShellApplication rather than writeShellScriptBin so that shellcheck
  # runs at build time.  Arguments are assembled in Nix and escaped in one go,
  # which keeps the generated body a single well-quoted line rather than a
  # continuation whose optional parts can collapse to an empty argument.
  launcher = pkgs.writeShellApplication {
    name = "hydrus-attach";
    runtimeInputs = [ cfg.package ];
    text = ''
      exec xpra attach ${lib.escapeShellArgs attachArgs} "$@"
    '';
  };
in
{
  options.programs.hydrus-client = {
    enable = lib.mkEnableOption "an xpra launcher for a Hydrus GUI hosted elsewhere";

    package = lib.mkPackageOption pkgs "xpra" { };

    host = lib.mkOption {
      type = lib.types.str;
      example = "meyeri";
      description = ''
        Host running {option}`services.hydrus.client` with an xpra TCP listener.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 14500;
      description = ''
        Port of that listener.  14500 is xpra's conventional port, and is what
        the host's `--bind-tcp` should be set to.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/home/eric/.config/xpra/hydrus-password";
      description = ''
        Path to a file holding the password for the session, matching the one
        the host gives xpra's `file` auth module.  Read by the xpra client at
        attach time, so it is a path on *this* machine.

        Leave null only when the host's listener has no authentication, which
        means anyone able to reach the port has full control of the library.
      '';
    };

    extraAttachArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--opengl=no" ];
      description = "Extra arguments to pass to `xpra attach`.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = ''
          programs.hydrus-client needs pkgs.xpra, which nixpkgs builds for
          Linux only.  On Darwin, reach the same session with xpra's HTML5
          client instead: http://${cfg.host}:${toString cfg.port}/
        '';
      }
    ];

    home.packages = [
      cfg.package
      launcher
    ];
  };
}
