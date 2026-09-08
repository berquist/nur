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
# Three ways that equivalence breaks.  Only the first can be fatal, and only
# then in the two cases spelled out below -- which is the reason this script
# warns rather than pretending to be authoritative:
#
#   `.gitattributes` export-subst, but only for *some* placeholders.  A file
#   marked with it has its `$Format:...$` expanded at archive time, and two of
#   those expansions differ between here and GitHub's servers:
#
#     - `%d` / `%D` (ref-names) lists the refs pointing at the commit, which
#       here means local branches and remotes and there means almost nothing.
#       Always fatal.
#     - `%(describe...)` is fatal only when the commit is *past* a tag: the
#       output then carries a `-<n>-g<sha>` suffix whose abbreviation length is
#       the archiving repository's choice -- ten characters on GitHub, nine in a
#       small local clone.  On a commit that *is* a tag, the output is the bare
#       tag name and both sides agree.
#
#   Anything else in a `$Format:$` -- `%H`, `%cI`, `%ct` -- is a property of the
#   commit and matches.  So this is checked by reading the marked files rather
#   than by the presence of the attribute: sisl is the fatal case (ref-names
#   *and* a non-tag describe), while dargs and deepmd-kit are the safe one, and
#   their hashes were confirmed against real builds before this was relaxed.
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

    # export-subst is only *sometimes* fatal, and which it is depends on the
    # placeholders rather than on the attribute.  Two of them differ between
    # this clone and GitHub's servers:
    #
    #   %d / %D (ref-names) lists the refs pointing at the commit, which here
    #   includes local branches and remotes and there does not.  Always fatal.
    #
    #   %(describe...) is fatal only when the commit is *past* a tag, because
    #   then the output carries a `-<n>-g<sha>` suffix and the abbreviation
    #   length is chosen by the archiving repository -- ten characters on
    #   GitHub, nine in a small local clone.  On a commit that *is* a tag the
    #   output is just the tag name, identical on both sides.
    #
    # Everything else -- %H, %h's siblings, %cI, %ct -- is a property of the
    # commit and matches.  sisl is the fatal case (its .git_archival.txt has
    # both a ref-names field and a non-tag describe); dargs and deepmd-kit are
    # the safe one, and their hashes were confirmed by a real build.
    if grep -q 'export-subst' "$attributes"; then
        mapfile -t subst_paths < <(
            grep 'export-subst' "$attributes" | awk '{ print $1 }'
        )
        subst_content=""
        for path in "${subst_paths[@]}"; do
            subst_content+=$(git -C "$clone" show "$full_rev:$path" 2>/dev/null || true)
        done

        reason=""
        # shellcheck disable=SC2016  # $Format:...$ is git's literal placeholder
        # syntax being matched, not a shell expansion.
        if grep -qE '\$Format:[^$]*%[dD]' <<<"$subst_content"; then
            reason="a ref-names placeholder, which lists this clone's own refs"
        elif grep -q 'describe' <<<"$subst_content" && [[ $described == *-g* ]]; then
            reason="a describe placeholder, and $described is past a tag rather than on one"
        fi

        if [[ -n $reason ]]; then
            printf 'ERROR: %s marks files export-subst, and one of them has\n' "$rel" >&2
            printf '       %s.\n' "$reason" >&2
            printf '       THE HASH BELOW WILL NOT MATCH.  Take the real one from the\n' >&2
            printf '       hash mismatch a build prints.\n' >&2
            exit_code=1
        else
            printf 'note: %s marks files export-subst, but their placeholders all\n' "$rel" >&2
            printf '      expand identically here and on GitHub (no ref-names field, and\n' >&2
            printf '      %s is a tag rather than a commit past one), so the\n' "$described" >&2
            printf '      hash below still stands.\n' >&2
        fi
    fi
done

exit_code=${exit_code:-0}

printf 'rev       %s\n' "$full_rev"
printf 'describe  %s\n' "$described"
printf 'date      %s\n' "$date"
printf 'hash      %s\n' "$(nix hash path "$tree")"

exit "$exit_code"
