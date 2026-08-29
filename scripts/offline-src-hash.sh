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
# Three ways that equivalence breaks.  Only the first is fatal, and it is the
# reason this script warns rather than pretending to be authoritative:
#
#   `.gitattributes` export-subst.  A file marked with it has its `$Format:...$`
#   placeholders expanded at archive time, and the expansion is not the same on
#   both sides.  `%(describe)` abbreviates the hash to whatever the archiving
#   repository's `core.abbrev` heuristic picks -- ten characters on GitHub's
#   servers, nine in a small local clone -- and `ref-names` lists the local
#   refs, which are `HEAD -> main, origin/main` here and empty there.  sisl is
#   the example: its .git_archival.txt differs in exactly those two fields, so
#   the offline hash cannot match and the only honest source of the real one is
#   a build that fails and prints it.
#
#   Submodules.  These are fine, contrary to what this script used to do: a
#   codeload tarball keeps the submodule path as an *empty directory*, and so
#   does `git archive`, so the two agree with `fetchSubmodules = false`.  This
#   was verified against pkgs/chemfiles-python, whose hash came from a real
#   build and matches the tree with the empty `lib/` left in place.  A package
#   that needs the submodule's *contents* is a different matter and cannot use
#   this script's answer at all.
#
#   `.gitattributes` export-ignore.  Both sides honour it, so the hash still
#   matches, but the *source tree* silently loses whatever is marked --
#   frequently `tests/`, which is the sdist-has-no-tests trap wearing a
#   different hat (see AGENTS.md).  Warned about for that reason, not for the
#   hash's sake.
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

# Submodule paths are deliberately left alone; see the header.  They are still
# worth mentioning, because a package needing their contents wants
# `fetchSubmodules = true`, which this hash is not.
if [[ -f $tree/.gitmodules ]]; then
    printf 'note: submodules are present and kept as empty directories:\n' >&2
    git -C "$clone" config --file "$tree/.gitmodules" \
        --get-regexp '^submodule\..*\.path$' | sed 's/^.*\.path /  /' >&2
    printf '      (a package that needs their contents wants fetchSubmodules = true,\n' >&2
    printf '       whose hash is a different one entirely)\n' >&2
fi

# One warning is advisory, the other says the answer below is wrong.
mapfile -t attributes_files < <(find "$tree" -name .gitattributes -type f)

for attributes in "${attributes_files[@]}"; do
    rel=${attributes#"$tree"/}

    if grep -q 'export-ignore' "$attributes"; then
        printf 'warning: %s has export-ignore entries; this tree is missing:\n' "$rel" >&2
        grep 'export-ignore' "$attributes" | sed 's/^/  /' >&2
    fi

    if grep -q 'export-subst' "$attributes"; then
        printf 'ERROR: %s marks files export-subst:\n' "$rel" >&2
        grep 'export-subst' "$attributes" | sed 's/^/  /' >&2
        # shellcheck disable=SC2016  # $Format:...$ is the literal git syntax,
        # not a shell expansion.
        printf '       Their $Format:...$ placeholders expand differently here than on\n' >&2
        printf '       GitHub -- describe-name abbreviates to a different length, and\n' >&2
        printf '       ref-names lists this clone.  THE HASH BELOW WILL NOT MATCH.\n' >&2
        printf '       Take the real one from the hash mismatch a build prints.\n' >&2
        exit_code=1
    fi
done

exit_code=${exit_code:-0}

printf 'rev       %s\n' "$full_rev"
printf 'describe  %s\n' "$described"
printf 'date      %s\n' "$date"
printf 'hash      %s\n' "$(nix hash path "$tree")"

exit "$exit_code"
