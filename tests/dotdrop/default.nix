# tests/dotdrop/default.nix
#
# Integration tests for the dotdrop package.
#
# Run all tests:
#   nix-build tests -A dotdrop.all
#
# Run one test:
#   nix-build tests -A dotdrop.roundtrip
#   nix-build tests -A dotdrop.tests-ng
#
# Or directly, bypassing tests/default.nix:
#   nix-build tests/dotdrop -A roundtrip
#
# These are runCommand builds, not VM tests — dotdrop is a plain CLI with no
# NixOS module, so there is nothing to boot.  They do need a real build of the
# package, so unlike tests/qcarchive/default.nix they cannot run under a
# daemon-less evaluation.
#
# pkgs must have the dotdrop overlay applied; the default argument does it.
{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).dotdrop ];
  },
}:

let
  inherit (pkgs) lib dotdrop;

  # Every test below ends in `mkdir $out`, never `touch $out`: the `all` target
  # is a symlinkJoin, which lndirs each path and dies with "Not a directory" on
  # a plain file.  tests/qcarchive/default.nix's `check` helper has the same
  # constraint for the same reason.

  # Everything tests-ng/ shells out to.  `file` and `diffutils` are deliberately
  # NOT listed: dotdrop needs both at runtime and its wrapper is what must
  # supply them, so leaving them out of PATH here is precisely what makes
  # `tests-ng` a regression test for the makeWrapperArgs in ../../pkgs/dotdrop.
  testTools = [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.ncurses # tput; see the TERM note below for why it is here at all
    pkgs.tree
  ];

in
rec {
  # ==========================================================================
  # Upstream's own end-to-end suite, run against the *installed* binary.
  #
  # Every tests-ng script honours $DT_BIN; without it they fall back to
  # `python3 -m dotdrop.dotdrop` against a source checkout, which would test
  # upstream rather than our packaging.  Pointing DT_BIN at
  # ${dotdrop}/bin/dotdrop makes these exercise the console-script entry point,
  # the runtime dependency closure, the wrapper's PATH, python-magic's patched
  # libmagic and Jinja2 templating — none of which the pytest suite in the
  # derivation's checkPhase can see, since it imports the package directly.
  #
  # A subset, not all 154: this is a packaging check, not a fork of upstream
  # CI.  These were picked to cover one distinct runtime dependency or code
  # path each, and are cheap.  The pytest suite already runs in checkPhase.
  # ==========================================================================
  tests-ng =
    let
      # scriptName -> what it is here to prove
      scripts = {
        import = "the plain import path, and re-import idempotency";
        install = "the plain install path, with Jinja2 template expansion";
        env = "environment variables reaching the template engine";
        toml = "TOML configs — tomllib on read, tomli_w on write";
        compare = "the diff_command validation in Settings, and diff itself";
        # transformations.sh, not import-with-trans.sh: the latter covers the
        # same code path but picks gpg as its example transformation, and gpg
        # is a dependency of that *script*, not of dotdrop.  Pulling gnupg in
        # to satisfy it would add a gpg-agent and a GNUPGHOME to a build
        # sandbox for no packaging coverage.  transformations.sh pipes through
        # base64 and cat, which are already here.
        transformations = "trans_read/trans_write, which pipe through a shell command";
        "install-ignore" = "ignore patterns over a real install";
        "link-value-tests" = "the three link modes end to end";
        workers = "the DOTDROP_WORKERS parallel path";
        "uninstall-by-key" = "removal, the inverse of install";
      };
    in
    pkgs.runCommand "dotdrop-tests-ng"
      {
        nativeBuildInputs = [ dotdrop ] ++ testTools;
        meta.description = "upstream dotdrop tests-ng scripts run against the installed binary";
      }
      ''
        set -euo pipefail

        # tests-ng writes into $HOME/.config/dotdrop and mktemp dirs.
        export HOME="$(mktemp -d)"
        export DOTDROP_WORKDIR="$(mktemp -d)"

        # The one knob that makes this test our packaging rather than upstream's
        # source tree.
        export DT_BIN="${lib.getExe dotdrop}"

        # Every script colourises its header with `$(tput setaf 6)`.  tput
        # cannot succeed in a build sandbox whatever we do — nixpkgs configures
        # ncurses with --with-terminfo-dirs pointing at /etc/terminfo and
        # friends, none of which exist here — but every call site is inside a
        # command substitution, so the failure never becomes the command's exit
        # status and `set -e` never sees it.  Setting TERM just keeps tput from
        # additionally complaining that it is unset.
        export TERM=dumb

        cp -r --no-preserve=mode,ownership ${dotdrop.src}/tests-ng .
        cd tests-ng

        # `hash coverage` in each script's header would otherwise switch $bin to
        # a coverage invocation and ignore DT_BIN.  coverage is not in PATH
        # here, but be explicit rather than relying on that.
        unset DOTDROP_WORKERS

        fail=0
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: why: ''
            echo "==> ${name}: ${why}"
            if bash ./${name}.sh; then
              echo "    ok"
            else
              echo "    FAIL: ${name}.sh (${why})"
              fail=1
            fi
          '') scripts
        )}

        [ "$fail" = "0" ] || { echo "one or more tests-ng scripts failed"; exit 1; }
        echo "all ${toString (lib.length (lib.attrNames scripts))} tests-ng scripts passed"
        mkdir $out
      '';

  # ==========================================================================
  # A hand-written round trip.
  #
  # Deliberately does not reuse anything from tests-ng: it is the readable
  # statement of what we actually care about (import a file, install it back
  # out, get the same content with the profile substituted), and it keeps
  # working if upstream renames or drops the scripts selected above.
  # ==========================================================================
  roundtrip =
    pkgs.runCommand "dotdrop-roundtrip"
      {
        nativeBuildInputs = [ dotdrop ] ++ testTools;
        meta.description = "import a dotfile and install it back out via the packaged dotdrop";
      }
      ''
        set -euo pipefail
        export HOME="$(mktemp -d)"
        cd "$HOME"

        mkdir -p src dotfiles

        # A template, so this also proves Jinja2 is wired up: {{@@ profile @@}}
        # must expand to the profile name on install.
        printf 'export EDITOR=vi\n# managed by dotdrop for {{@@ profile @@}}\n' > src/bashrc

        cat > config.yaml <<'EOF'
        config:
          backup: false
          create: true
          dotpath: dotfiles
        dotfiles:
        profiles:
        EOF

        # --- import -------------------------------------------------------
        dotdrop import -c config.yaml -p laptop -f "$HOME/src/bashrc"

        echo "--- config.yaml after import ---"
        cat config.yaml

        grep -q 'f_bashrc' config.yaml \
          || { echo "FAIL: dotfile key absent from config"; exit 1; }
        grep -q 'laptop' config.yaml \
          || { echo "FAIL: profile absent from config"; exit 1; }

        # Where the copy landed under dotpath is NOT simply dotpath + the
        # absolute source path: dotdrop strips $HOME first, so importing
        # ~/src/bashrc records `src: src/bashrc` and `dst: ~/src/bashrc`, while
        # importing from outside home mirrors the full path instead (which is
        # what upstream's tests-ng/import.sh exercises).  Read the location back
        # out of the config rather than predicting it.
        stored="dotfiles/$(sed -n 's/^ *src: *//p' config.yaml | head -1)"
        echo "stored copy: $stored"
        test -f "$stored" \
          || { echo "FAIL: nothing landed under dotpath"; find dotfiles; exit 1; }

        # The stored copy must be byte-identical to what we imported: import
        # copies, it does not template.
        cmp src/bashrc "$stored" \
          || { echo "FAIL: imported copy differs from the original"; exit 1; }

        # --- install ------------------------------------------------------
        # Delete the original first, so install has to genuinely recreate it and
        # cannot pass by leaving what was already there in place.
        rm src/bashrc
        dotdrop install -c config.yaml -p laptop -f

        test -f src/bashrc \
          || { echo "FAIL: install did not recreate the dotfile"; find "$HOME"; exit 1; }
        grep -q '^export EDITOR=vi$' src/bashrc \
          || { echo "FAIL: literal content did not survive install"; cat src/bashrc; exit 1; }
        grep -q '# managed by dotdrop for laptop$' src/bashrc \
          || { echo "FAIL: {{@@ profile @@}} was not expanded by Jinja2"; cat src/bashrc; exit 1; }

        # A second install must be a no-op rather than an error.
        dotdrop install -c config.yaml -p laptop -f
        grep -q '# managed by dotdrop for laptop$' src/bashrc \
          || { echo "FAIL: re-install corrupted the installed file"; cat src/bashrc; exit 1; }

        # --- compare ------------------------------------------------------
        # Exercises the diff_command path in Settings, which is the other thing
        # the wrapper's PATH has to satisfy.  Nothing has diverged, so this
        # reports no difference and exits 0.
        dotdrop compare -c config.yaml -p laptop

        echo "round trip OK"
        mkdir $out
      '';

  # ==========================================================================
  # The packaging invariants that do not need a round trip.
  # ==========================================================================
  metadata =
    pkgs.runCommand "dotdrop-metadata"
      {
        nativeBuildInputs = [ dotdrop ];
        meta.description = "entry point, version, man page and completions are installed";
      }
      ''
        set -euo pipefail

        # mainProgram must actually exist: the console script is named after
        # the package here, but lib.getExe falls back to the package name
        # silently, so assert rather than assume.
        test -x "${lib.getExe dotdrop}" \
          || { echo "FAIL: ${lib.getExe dotdrop} is not executable"; exit 1; }

        # --version must agree with the version attribute, which is the thing
        # that silently rots after a bump.
        got="$(dotdrop --version 2>&1 | tr -d '\n')"
        echo "dotdrop --version -> $got"
        case "$got" in
          *${dotdrop.version}*) ;;
          *) echo "FAIL: expected ${dotdrop.version} in --version output"; exit 1 ;;
        esac

        test -f "${dotdrop}/share/man/man1/dotdrop.1.gz" \
          || { echo "FAIL: man page not installed"; exit 1; }
        test -f "${dotdrop}/share/bash-completion/completions/dotdrop.bash" \
          || { echo "FAIL: bash completion not installed"; exit 1; }
        test -f "${dotdrop}/share/zsh/site-functions/_dotdrop" \
          || { echo "FAIL: zsh completion not installed"; exit 1; }
        test -f "${dotdrop}/share/fish/vendor_completions.d/dotdrop.fish" \
          || { echo "FAIL: fish completion not installed"; exit 1; }

        echo "metadata OK"
        mkdir $out
      '';

  # ==========================================================================
  # Convenience target: build all tests at once.
  #
  # Hand-maintained, like tests/qcarchive/default.nix's — new tests must be
  # added here too.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "dotdrop-tests";
    paths = [
      metadata
      roundtrip
      tests-ng
    ];
  };
}
