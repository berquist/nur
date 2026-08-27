# Static pollution-hazard scan over aiida-core's test suite.
#
#   nix-build tests/aiida/pollution-scan.nix --no-out-link && cat result
#   just aiida-pollution-scan
#
# Wraps ../../scripts/aiida-pollution-scan.py, whose docstring explains the three
# scans and why enumerating pairs beats sampling for them.
#
# The point of running it as a derivation rather than against a checkout is that
# the scan has to see the **patched** tree.  ../../pkgs/aiida-core/default.nix's
# postPatch is what adds the twelve `aiida_profile_clean` guards; scanning
# upstream's source instead would faithfully re-report every hazard this repo has
# already fixed, and the report would be ignored within a week.
#
# It does not build aiida-core.  The source is copied, postPatch is run over it,
# and the scan reads the result — seconds, not minutes, so this can be a routine
# check rather than something saved for when a build has already gone red.

{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).aiida ];
  },
}:

let
  inherit (pkgs) lib;

  py = pkgs.python313Packages;
  inherit (py) aiida-core;

  # The 0.x-format archives, which is where `testing1`..`testing4` live — the
  # rows that enter a profile through import_archive() with nothing under tests/
  # so much as naming them.  aiida-core's own tests/static/ carries the modern
  # ones; both roots are passed.
  migrationFixtures = py.aiida-export-migration-tests;
in
pkgs.runCommand "aiida-pollution-scan"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    meta = {
      description = "Cross-test pollution hazards in aiida-core's suite";
      inherit (aiida-core.meta) license maintainers;
    };
  }
  ''
    cp -r ${aiida-core.src} source
    chmod -R u+w source
    cd source

    # The same patch the package applies, so the guards already in place are not
    # reported as holes.  It is taken from the derivation rather than duplicated,
    # so the two cannot drift.
    ${aiida-core.postPatch}

    python3 ${../../scripts/aiida-pollution-scan.py} . \
      ./tests \
      ${lib.escapeShellArg "${migrationFixtures}/${py.python.sitePackages}"} \
      > "$out"
  ''
