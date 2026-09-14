# tests/anilist-mal-sync-module/default.nix
#
# Evaluation tests for the anilist-mal-sync NixOS module.
#
# Run all tests:
#   nix-build tests -A anilist-mal-sync-module.all
#
# Run one test:
#   nix-build tests -A anilist-mal-sync-module.defaults
#   nix-build tests -A anilist-mal-sync-module.assertion-missing-watch-config
#
# Or directly, bypassing tests/default.nix:
#   nix-build tests/anilist-mal-sync-module -A defaults
#
# Same shape as ../qcarchive/default.nix: the package is stubbed via an
# overlay (the only safe extension point with eval-config.nix), so these run
# under `just check-no-daemon` with nothing built. The package itself is
# covered by ../anilist-mal-sync/default.nix instead.

{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs) lib;

  stubOverlay = _final: _prev: {
    anilist-mal-sync = pkgs.runCommand "anilist-mal-sync-stub" {
      # lib.getExe's no-mainProgram fallback derives the binary name from
      # the derivation's *name* ("anilist-mal-sync-stub"), not from
      # whatever file actually exists under $out/bin -- so without this,
      # it resolves to bin/anilist-mal-sync-stub regardless of what gets
      # touched below. The real package sets this too.
      meta.mainProgram = "anilist-mal-sync";
    } "mkdir -p $out/bin && touch $out/bin/anilist-mal-sync";
  };

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

  eval =
    extraConfig:
    (nixosEval [
      ../../nixos-modules/anilist-mal-sync.nix
      extraConfig
    ]).config;

  # A minimal working config: enabled, with the one thing the module asserts
  # on. Most tests below extend this rather than repeating it.
  minimal = {
    services.anilist-mal-sync = {
      enable = true;
      environment.WATCH_INTERVAL = "24h";
    };
  };

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

  # Real (unstubbed) package set, used only by the overlay contract tests
  # below. Applied here rather than relying on the caller so that
  # `nix-build tests -A anilist-mal-sync-module.all` works with a plain
  # <nixpkgs>.
  overlaidPkgs = pkgs.extend (import ../../overlays).anilist-mal-sync;

  execStartOf = cfg: cfg.systemd.services.anilist-mal-sync.serviceConfig.ExecStart;

  loginScriptOf =
    cfg:
    lib.findFirst (p: (p.name or "") == "anilist-mal-sync-login") null cfg.environment.systemPackages;
in
lib.fix (self: {
  # ==========================================================================
  # Overlay contract
  #
  # Everything else here stubs pkgs.anilist-mal-sync, so it cannot notice if
  # the overlay stops providing it. Evaluation only -- nothing is built.
  # ==========================================================================

  # mkPackageOption resolves against the top level of pkgs, not through any
  # python*Packages set -- this is a Go package, so there is no such set to
  # begin with, but the module still needs pkgs.anilist-mal-sync to exist.
  overlay-toplevel-package = check "overlay-toplevel-package" (
    overlaidPkgs ? anilist-mal-sync
    &&
      overlaidPkgs.anilist-mal-sync == (import ../../default.nix { pkgs = overlaidPkgs; })
      .anilist-mal-sync
  );

  # The service invokes the package via lib.getExe, which falls back to the
  # package *name* when meta.mainProgram is unset -- here the two happen to
  # agree, so assert rather than assume.
  overlay-main-program = check "overlay-main-program" (
    lib.hasSuffix "/bin/anilist-mal-sync" (lib.getExe overlaidPkgs.anilist-mal-sync)
  );

  # ==========================================================================
  # Disabled: nothing created.
  # ==========================================================================
  disabled = check "disabled" (
    let
      cfg = eval { };
    in
    !(cfg.systemd.services ? anilist-mal-sync) && loginScriptOf cfg == null
  );

  # ==========================================================================
  # Enabled, defaults: plain ExecStart, no extra flags, state wired up.
  # ==========================================================================
  defaults = check "defaults" (
    let
      cfg = eval minimal;
      unit = cfg.systemd.services.anilist-mal-sync;
    in
    lib.hasSuffix "/bin/anilist-mal-sync watch --once" (execStartOf cfg)
    && unit.serviceConfig.WorkingDirectory == "/var/lib/anilist-mal-sync"
    && unit.environment.XDG_CONFIG_HOME == "/var/lib/anilist-mal-sync"
    && !(unit.serviceConfig ? EnvironmentFile)
    && cfg.users.users ? anilist-mal-sync
    && cfg.users.users.anilist-mal-sync.isSystemUser
    && cfg.users.groups ? anilist-mal-sync
    && loginScriptOf cfg != null
  );

  # ==========================================================================
  # environmentFile: read at start, and only then.
  # ==========================================================================
  environment-file-set = check "environment-file-set" (
    let
      cfg = eval (
        lib.recursiveUpdate minimal {
          services.anilist-mal-sync.environmentFile = "/run/secrets/anilist-mal-sync-credentials";
        }
      );
    in
    cfg.systemd.services.anilist-mal-sync.serviceConfig.EnvironmentFile
    == "/run/secrets/anilist-mal-sync-credentials"
  );

  # ==========================================================================
  # syncTarget / reverseDirection: these have no environment-variable form
  # upstream, so the module appends CLI flags instead -- the one part of
  # ExecStart worth a regression test per value.
  # ==========================================================================
  sync-target-anime-default = check "sync-target-anime-default" (
    !(lib.hasInfix "--manga" (execStartOf (eval minimal)))
    && !(lib.hasInfix "--all" (execStartOf (eval minimal)))
  );

  sync-target-manga = check "sync-target-manga" (
    let
      cfg = eval (lib.recursiveUpdate minimal { services.anilist-mal-sync.syncTarget = "manga"; });
    in
    lib.hasSuffix "--manga" (execStartOf cfg) && !(lib.hasInfix "--all" (execStartOf cfg))
  );

  sync-target-all = check "sync-target-all" (
    let
      cfg = eval (lib.recursiveUpdate minimal { services.anilist-mal-sync.syncTarget = "all"; });
    in
    lib.hasSuffix "--all" (execStartOf cfg) && !(lib.hasInfix "--manga" (execStartOf cfg))
  );

  reverse-direction = check "reverse-direction" (
    let
      cfg = eval (lib.recursiveUpdate minimal { services.anilist-mal-sync.reverseDirection = true; });
    in
    lib.hasSuffix "--reverse-direction" (execStartOf cfg)
  );

  reverse-direction-default-off = check "reverse-direction-default-off" (
    !(lib.hasInfix "--reverse-direction" (execStartOf (eval minimal)))
  );

  # Flags must combine rather than one overwriting another.
  sync-target-and-reverse-combine = check "sync-target-and-reverse-combine" (
    let
      cfg = eval (
        lib.recursiveUpdate minimal {
          services.anilist-mal-sync = {
            syncTarget = "all";
            reverseDirection = true;
          };
        }
      );
      s = execStartOf cfg;
    in
    lib.hasInfix "--all" s && lib.hasInfix "--reverse-direction" s
  );

  # ==========================================================================
  # anilist-mal-sync-login: privilege check and the same environmentFile,
  # since it re-execs as cfg.user and sources the file directly rather than
  # relying on systemd's own EnvironmentFile= read as PID 1 -- see the note
  # in ../../nixos-modules/anilist-mal-sync.nix and the "not read by PID 1"
  # precedent in ../../nixos-modules/qcfractal-server.nix.
  # ==========================================================================
  login-script = check "login-script" (
    let
      cfg = eval (
        lib.recursiveUpdate minimal {
          services.anilist-mal-sync.environmentFile = "/run/secrets/anilist-mal-sync-credentials";
        }
      );
      s = (loginScriptOf cfg).text;
    in
    lib.hasInfix "runuser -u 'anilist-mal-sync'" s
    && lib.hasInfix "/run/secrets/anilist-mal-sync-credentials" s
    && lib.hasInfix "login" s
    # --help/--version must be answered before the privilege check, the same
    # reasoning as qcfractal-manage.
    && lib.hasInfix "--version)" s
  );

  # ==========================================================================
  # oauthPort / openFirewall
  # ==========================================================================
  no-firewall-by-default = check "no-firewall-by-default" (
    !(builtins.elem 18080 (eval minimal).networking.firewall.allowedTCPPorts)
  );

  open-firewall = check "open-firewall" (
    let
      cfg = eval (lib.recursiveUpdate minimal { services.anilist-mal-sync.openFirewall = true; });
    in
    builtins.elem 18080 cfg.networking.firewall.allowedTCPPorts
  );

  custom-oauth-port = check "custom-oauth-port" (
    let
      cfg = eval (
        lib.recursiveUpdate minimal {
          services.anilist-mal-sync = {
            openFirewall = true;
            oauthPort = 9999;
          };
        }
      );
    in
    builtins.elem 9999 cfg.networking.firewall.allowedTCPPorts
  );

  # ==========================================================================
  # stateDir / user
  # ==========================================================================
  custom-state-dir = check "custom-state-dir" (
    let
      cfg = eval (
        lib.recursiveUpdate minimal { services.anilist-mal-sync.stateDir = "/srv/anilist-mal-sync"; }
      );
      unit = cfg.systemd.services.anilist-mal-sync;
    in
    unit.serviceConfig.WorkingDirectory == "/srv/anilist-mal-sync"
    && unit.environment.XDG_CONFIG_HOME == "/srv/anilist-mal-sync"
  );

  # A custom user is expected to already exist, so the module must not also
  # try to create the default "anilist-mal-sync" one under a different name.
  custom-user-skips-default-user = check "custom-user-skips-default-user" (
    let
      cfg = eval (lib.recursiveUpdate minimal { services.anilist-mal-sync.user = "other"; });
    in
    !(cfg.users.users ? anilist-mal-sync)
  );

  # ==========================================================================
  # Assertion violations (must throw during evaluation)
  # ==========================================================================
  assertion-missing-watch-config = assertFails "assertion-missing-watch-config" (nixosEval [
    ../../nixos-modules/anilist-mal-sync.nix
    { services.anilist-mal-sync.enable = true; }
  ]);

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "anilist-mal-sync-module-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
