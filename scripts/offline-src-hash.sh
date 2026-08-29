#!/usr/bin/env bash
#
# Compute a fetchFromGitHub `hash` from a local clone, with no network and no
# nix-daemon.
#
#   scripts/offline-src-hash.sh wc/aiida/aiida-shell [rev]
#
# Every packaging session here starts by pinning a `rev` that is already sitting
# in wc/, and `nix-prefetch-url`/`nix flake prefetch` both want the network the
# Claude Code sandbox does not have.  `git archive` reproduces exactly the tree
# GitHub's codeload tarball carries, so hashing that tree offline gives the same
# NAR hash fetchFromGitHub will later check against.
#
# Two ways that equivalence breaks, both encoded below rather than left to be
# rediscovered:
#
#   Submodules.  GitHub's tarball omits a submodule path entirely; `git archive`
#   leaves an empty directory in its place, and an empty directory changes the
#   NAR.  They are removed here, which matches fetchFromGitHub's default
#   `fetchSubmodules = false`.  A package that needs the submodule contents
#   cannot use this script's answer at all -- see pkgs/chemfiles-python for what
#   that case looks like.
#
#   `.gitattributes` export-ignore.  Both `git archive` and codeload honour it,
#   so the hash still matches, but the *source tree* silently loses whatever is
#   marked -- frequently `tests/`, which is the sdist-has-no-tests trap wearing
#   a different hat (see AGENTS.md).  A warning is printed so it is noticed
#   before a green build with zero collected tests is believed.
#
# Also prints the rev and the commit date, which are the other two things a new
# derivation needs: the repo's version scheme for an untagged commit is
# `X.Y.Z-unstable-YYYY-MM-DD`.

set -euo pipefail

usage() {
    printf 'usage: %s <clone-dir> [rev]\n' "${0##*/}" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

clone=$1
rev=${2:-HEAD}

[[ -d $clone ]] || {
    printf 'offline-src-hash.sh: no such directory: %s\n' "$clone" >&2
    exit 1
}

git -C "$clone" rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'offline-src-hash.sh: not a git clone: %s\n' "$clone" >&2
    exit 1
}

full_rev=$(git -C "$clone" rev-parse "$rev^{commit}")
date=$(git -C "$clone" log -1 --format=%cs "$full_rev")
described=$(git -C "$clone" describe --tags --always "$full_rev" 2>/dev/null || echo "$full_rev")

tree=$(mktemp -d "${TMPDIR:-/tmp}/offline-src-hash.XXXXXX")
trap 'rm -rf "$tree"' EXIT

git -C "$clone" archive --format=tar "$full_rev" | tar -x -C "$tree"

if [[ -f $tree/.gitmodules ]]; then
    mapfile -t submodules < <(
        git -C "$clone" config --file "$tree/.gitmodules" \
            --get-regexp '^submodule\..*\.path$' | cut -d' ' -f2-
    )
    for path in "${submodules[@]}"; do
        [[ -n $path ]] || continue
        printf 'note: dropping submodule path %s (fetchSubmodules = false)\n' "$path" >&2
        rm -rf "${tree:?}/$path"
    done
fi

if [[ -f $tree/.gitattributes ]] && grep -q 'export-ignore' "$tree/.gitattributes"; then
    printf 'warning: .gitattributes has export-ignore entries; this tree is missing:\n' >&2
    grep 'export-ignore' "$tree/.gitattributes" | sed 's/^/  /' >&2
fi

printf 'rev       %s\n' "$full_rev"
printf 'describe  %s\n' "$described"
printf 'date      %s\n' "$date"
printf 'hash      %s\n' "$(nix hash path "$tree")"
