# Older nixpkgs revisions, pinned for the three NOMAD downgrades.
#
# nomad-lab caps httpx below 0.28, plotly below 6, beautifulsoup4 at 4.12.3 and
# fastapi below 0.137 — all of which nixpkgs-unstable has moved past.  Rather
# than hand-write four downgraded derivations and inherit the job of
# maintaining their test configuration, take the *expression* from a revision
# that already carried the right version:
#
#   pyfinal.callPackage "${pins.nixpkgs-2411}/pkgs/development/python-modules/httpx" { }
#
# Note "expression", not package.  Taking nixpkgs-2411.python313Packages.httpx
# would drag that revision's entire closure — its pydantic, its numpy — into an
# environment alongside ours, putting two pydantics on one PYTHONPATH.
# callPackage'ing the directory gets today's dependencies with that revision's
# version.
#
# Why builtins.fetchTarball rather than flake inputs, which would be tracked in
# flake.lock: overlays/ has to work from ../../default.nix and ../../overlay.nix
# too, and those are plain non-flake entry points with no access to flake
# inputs (this is why the existing nixpkgs-qchem input is used only inside
# flake.nix's perSystem, never in an overlay).  A hash-pinned fetchTarball is
# the one form that works from both, and it is still pure: `nix flake check`
# accepts eval-time fetchers that carry a fixed hash.
#
# The hashes are the revisions' narHashes, read from
#   nix flake metadata --json github:NixOS/nixpkgs/<rev> | jq -r .locked.narHash
# Bump a revision by editing rev and sha256 together, never one alone.
{
  # nixos-24.11 carries the exact versions nomad-lab's own lock file pins:
  # httpx 0.27.2, plotly 5.24.1, beautifulsoup4 4.12.3.
  nixpkgs-2411 = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/50ab793786d9de88ee30ec4e4c24fb4236fc2674.tar.gz";
    sha256 = "sha256-/bVBlRpECLVzjV19t5KMdMFWSwKLtb5RyXdjz3LJT+g=";
  };

  # fastapi 0.136.3 — the last revision before nixpkgs bumped to 0.139.0.
  #
  # fastapi cannot come from nixos-24.11 with the other three.  That branch has
  # fastapi 0.115.3, which nominally satisfies nomad-lab's `<0.137.0`, but
  # 0.115 declares `starlette<0.42` while nomad-lab requires
  # `starlette>=1.3.1` — Starlette's 0.4x -> 1.x rewrite sits between them.
  # The 0.136 line declares `starlette>=0.46.0` with no ceiling, and is the
  # only one that satisfies both constraints at once.
  nixpkgs-fastapi136 = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/0a1b373a6762ee98990ee250af47e7421ef7e3bf.tar.gz";
    sha256 = "sha256-DvGAwnHAGzimsmQWVReOCoYV+wdJjW+/HY1ZxxFg4ZU=";
  };
}
