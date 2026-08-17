# tests/harmonwig/default.nix
#
# Integration tests for the harmonwig package.
#
# Run all tests:
#   nix-build tests -A harmonwig.all
#
# Run one test:
#   nix-build tests -A harmonwig.metadata
#   nix-build tests -A harmonwig.cli-errors
#
# These are runCommand builds against the *installed* binary, in the same shape
# as ../dotdrop/default.nix: harmonwig is a plain CLI with no NixOS module, so
# there is nothing to boot, but there is a real build to exercise.
#
# Unlike the dotdrop suite the default argument here cannot work.  harmonwig's
# cclib comes from upstream cclib's own flake, and ../../overlays is imported
# without flakes — see ../../pkgs/harmonwig/default.nix.  A harmonwig built from
# the bare NUR path carries meta.broken and has no cclib in its environment, so
# these tests are reachable only through the flake, which passes the composed
# package set in.
{
  pkgs ? throw ''
    tests/harmonwig: harmonwig needs cclib, which comes from the cclib flake
    input.  Use the flake:
      nix build .#checks.x86_64-linux.harmonwig
    or pass a package set that has both overlays applied:
      nix-build tests/harmonwig -A metadata --arg pkgs '<package set>'
  '',
}:

let
  inherit (pkgs) lib harmonwig;

  # Every test ends in `mkdir $out`, never `touch $out`: `all` is a symlinkJoin,
  # which lndirs each path and dies with "Not a directory" on a plain file.
  # Same constraint as ../dotdrop/default.nix and ../qcarchive/default.nix.

in
lib.fix (self: {
  # ==========================================================================
  # The packaging invariants.
  #
  # There is no --version flag, so unlike the dotdrop metadata test there is
  # nothing to cross-check harmonwig.version against; --help is the only thing
  # the CLI will say about itself.
  # ==========================================================================
  metadata =
    pkgs.runCommand "harmonwig-metadata"
      {
        nativeBuildInputs = [ harmonwig ];
        meta.description = "entry point exists and the CLI describes itself";
      }
      ''
        set -euo pipefail

        # mainProgram must actually exist.  lib.getExe falls back to the
        # package name without complaint, and here the two happen to agree —
        # so assert rather than assume, because a rename upstream would make
        # this silently resolve to a path that is not there.
        test -x "${lib.getExe harmonwig}" \
          || { echo "FAIL: ${lib.getExe harmonwig} is not executable"; exit 1; }

        got="$(harmonwig --help)"
        echo "$got"

        # The description and the prog name from src/harmonwig/__main__.py.
        case "$got" in
          *"Program for harmonic Wigner sampling"*) ;;
          *) echo "FAIL: --help did not print the program description"; exit 1 ;;
        esac
        case "$got" in
          *"usage: harmonwig"*) ;;
          *) echo "FAIL: argparse prog name is not 'harmonwig'"; exit 1 ;;
        esac

        # The options main() reads.  A silent argparse change would otherwise
        # only surface in a sampling run.
        for opt in --nsamples --seed --freqthr --output-file; do
          case "$got" in
            *"$opt"*) ;;
            *) echo "FAIL: --help does not mention $opt"; exit 1 ;;
          esac
        done

        echo "metadata OK"
        mkdir $out
      '';

  # ==========================================================================
  # The two failure paths the CLI can reach without a real frequency
  # calculation.
  #
  # The second is the one that earns its keep: reaching "Could not read QM
  # output file" means `from cclib.io import ccread` succeeded *inside the
  # installed wrapper*, which is the only evidence available here that the
  # flake-provided cclib really landed in harmonwig's environment.  A missing
  # cclib would fail earlier, with an ImportError.
  #
  # There is no end-to-end sampling test: main() needs a cclib-parseable
  # frequency output and upstream ships none.  The physics is covered by
  # tests/test_harmonicwigner_class.py, which builds its molecule and normal
  # modes in fixtures and runs in the derivation's own checkPhase.
  # ==========================================================================
  cli-errors =
    pkgs.runCommand "harmonwig-cli-errors"
      {
        nativeBuildInputs = [ harmonwig ];
        meta.description = "the CLI's two reachable error paths, including the cclib import";
      }
      ''
        set -euo pipefail
        cd "$(mktemp -d)"

        # --- a path that is not there -------------------------------------
        if harmonwig missing.out > stdout.txt 2> stderr.txt; then
          echo "FAIL: harmonwig succeeded on a nonexistent file"
          exit 1
        fi
        cat stderr.txt
        grep -q "does not exist" stderr.txt \
          || { echo "FAIL: expected a 'does not exist' message"; exit 1; }

        # --- a real file cclib cannot make sense of -----------------------
        # An empty *regular* file, not /dev/null: main() checks
        # Path.is_file(), which is false for a character device, so /dev/null
        # would take the branch above instead and prove nothing.
        : > empty.out
        if harmonwig empty.out > stdout.txt 2> stderr.txt; then
          echo "FAIL: harmonwig succeeded on an unparseable file"
          exit 1
        fi
        cat stderr.txt
        grep -q "Could not read QM output file" stderr.txt \
          || { echo "FAIL: cclib's ccread was not reached"; exit 1; }

        echo "cli-errors OK"
        mkdir $out
      '';

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "harmonwig-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
