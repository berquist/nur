# tests/anilist-mal-sync/default.nix
#
# Integration tests for the anilist-mal-sync package.
#
# Run all tests:
#   nix-build tests -A anilist-mal-sync.all
#
# Run one test:
#   nix-build tests -A anilist-mal-sync.metadata
#   nix-build tests -A anilist-mal-sync.cli-errors
#
# Or directly, bypassing tests/default.nix:
#   nix-build tests/anilist-mal-sync -A metadata
#
# Same shape as ../dotdrop/default.nix and ../harmonwig/default.nix: a plain
# CLI, no VM needed, but a real build to exercise. Unlike harmonwig this
# overlay needs no flake input, so the default argument works and this is
# dispatched from tests/default.nix like dotdrop.
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).anilist-mal-sync ];
  },
}:

let
  inherit (pkgs) lib;
  inherit (pkgs) anilist-mal-sync;

  # Every test below ends in `mkdir $out`, never `touch $out`: the `all`
  # target is a symlinkJoin, which lndirs each path and dies with "Not a
  # directory" on a plain file. Same constraint as ../dotdrop/default.nix.
in
lib.fix (self: {
  # ==========================================================================
  # The packaging invariants: entry point resolves, and --version reports the
  # ldflags-injected string rather than the Go default "(devel)".
  # ==========================================================================
  metadata =
    pkgs.runCommand "anilist-mal-sync-metadata"
      {
        nativeBuildInputs = [ anilist-mal-sync ];
        meta.description = "entry point exists and --version reports the packaged tag";
      }
      ''
        set -euo pipefail

        # mainProgram must actually exist: lib.getExe falls back to the
        # package name silently, and here the two happen to agree, so assert
        # rather than assume.
        test -x "${lib.getExe anilist-mal-sync}" \
          || { echo "FAIL: ${lib.getExe anilist-mal-sync} is not executable"; exit 1; }

        got="$(anilist-mal-sync --version 2>&1)"
        echo "anilist-mal-sync --version -> $got"
        case "$got" in
          *"v${anilist-mal-sync.version}"*) ;;
          *) echo "FAIL: expected v${anilist-mal-sync.version} in --version output"; exit 1 ;;
        esac

        got="$(anilist-mal-sync --help 2>&1)"
        case "$got" in
          *"login"*"logout"*"status"*"sync"*"watch"*"unmapped"*) ;;
          *) echo "FAIL: --help is missing one of the expected subcommands"; echo "$got"; exit 1 ;;
        esac

        echo "metadata OK"
        mkdir $out
      '';

  # ==========================================================================
  # The one failure path reachable with no credentials, no config file and no
  # network: `status` loads its config before doing anything else, and with
  # neither a config file nor the required env vars set it fails there with a
  # named, stable message -- see config.go's loadConfigFromFile.
  # ==========================================================================
  cli-errors =
    pkgs.runCommand "anilist-mal-sync-cli-errors"
      {
        nativeBuildInputs = [ anilist-mal-sync ];
        meta.description = "status fails cleanly with no config and no credentials";
      }
      ''
        set -euo pipefail
        export HOME="$(mktemp -d)"
        export XDG_CONFIG_HOME="$HOME/.config"
        cd "$HOME"

        if anilist-mal-sync status > stdout.txt 2> stderr.txt; then
          echo "FAIL: status succeeded with no config and no credentials"
          cat stdout.txt stderr.txt
          exit 1
        fi
        cat stdout.txt stderr.txt
        grep -q "required environment variables not set" stderr.txt stdout.txt \
          || { echo "FAIL: expected the 'required environment variables not set' message"; exit 1; }

        echo "cli-errors OK"
        mkdir $out
      '';

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "anilist-mal-sync-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
