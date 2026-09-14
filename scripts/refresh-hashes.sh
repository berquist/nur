#!/usr/bin/env bash
#
# refresh-hashes.sh — build an attribute of ../default.nix and rewrite any
# fixed-output hash it disagrees with, until it stops disagreeing.
#
#   scripts/refresh-hashes.sh internalPackages.trexio
#   scripts/refresh-hashes.sh chemfiles 5
#
# `nix build -f` rather than `nix build .#`, and NIX_PATH from
# ./locked-nixpkgs.sh, to match ./update-packages.sh — which is the only caller.
# The two attributes that declare a secondary source are `chemfiles` and
# `internalPackages.trexio`, and the second is not a flake output at all, so the
# flake reference this used to build could never have realised it.
#
# This exists because `nix-update` rewrites exactly one source.  Six packages
# here have a second fetch, and two of those — ../pkgs/trexio and
# ../pkgs/chemfiles — have one whose rev is derived from `version`, so a version
# bump moves the rev and leaves the hash stale.  docs/version-updates.md called
# that case permanently manual.  It is not: nix prints the right answer in the
# mismatch, and reading it back is what this does.
#
#   error: hash mismatch in fixed-output derivation '/nix/store/…':
#            specified: sha256-AAAA…
#               got:    sha256-BBBB…
#
# The `specified` value is unique enough to be its own address — a base64 SHA
# does not collide with anything else in the tree — so the rewrite is a literal
# replacement in whichever tracked file holds it, with no need to know which
# binding it belongs to.  That is what makes this generic rather than a fix for
# two packages: any derivation whose secondary hash goes stale is covered, and
# a `lib.fakeHash` placeholder is covered too, since nix reports that as the
# specified value like any other.
#
# **It rewrites, it does not judge.**  A hash mismatch can also mean the
# upstream artifact changed under a rev that did not, which is a supply-chain
# signal and not a stale pin.  The caller is scripts/update-packages.sh, which
# only calls this straight after a bump it made itself, and the rewritten files
# land in a pull request a human reads.  Do not wire this into anything that
# merges unattended.
#
# Needs a nix-daemon and the network; it is the one part of the updater that
# cannot run inside the Claude Code sandbox.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

usage() {
    cat >&2 <<'EOF'
usage: refresh-hashes.sh ATTR [MAX_ROUNDS]

  ATTR        attribute of ../default.nix, e.g. chemfiles or internalPackages.trexio
  MAX_ROUNDS  give up after this many rewrites (default 5)

Exit status:
  0  the attribute builds, with or without a rewrite
  1  it still fails, and the failure is not a hash mismatch
  2  MAX_ROUNDS rewrites were made and it still disagrees
EOF
}

log() {
    printf 'refresh-hashes: %s\n' "$1" >&2
}

# The two spellings nix has used for the left-hand side.  CppNix and Lix both
# print "specified:" today; "wanted:" is what older releases printed, and
# matching both costs one alternation.
extract_hash() {
    local field="$1" text="$2"
    printf '%s\n' "$text" \
        | grep --extended-regexp --only-matching \
            "(${field}): *(sha256|sha512|sha1|md5)-[A-Za-z0-9+/=]+" \
        | head -n 1 \
        | grep --extended-regexp --only-matching '(sha256|sha512|sha1|md5)-[A-Za-z0-9+/=]+' \
        || true
}

# Replace one hash literal wherever it appears in a tracked file.  Restricted to
# files git knows about so that a match inside result/ or wc/ — someone else's
# checkout of the same upstream — can never be rewritten.
rewrite_hash() {
    local old="$1" new="$2"
    local -a files=()

    mapfile -t files < <(
        git -C "$repo_root" grep --files-with-matches --fixed-strings -- "$old" \
            || true
    )

    if [[ ${#files[@]} -eq 0 ]]; then
        log "nix reported ${old} but no tracked file contains it"
        return 1
    fi

    local file
    for file in "${files[@]}"; do
        # No sed: a base64 hash contains / and + freely, and escaping them for a
        # sed expression is exactly the kind of quoting that breaks silently.
        python3 - "$repo_root/$file" "$old" "$new" <<'PY'
import pathlib
import sys

path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
path.write_text(text.replace(old, new))
PY
        log "rewrote ${file}"
    done
}

main() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        usage
        exit 1
    fi

    local attr="$1"
    local max_rounds="${2:-5}"
    local round=0

    cd "$repo_root"

    # Only when the caller has not pinned it already; ./update-packages.sh
    # exports the same value before it gets here.
    if [[ -z "${NIX_PATH:-}" ]]; then
        NIX_PATH="$("${repo_root}/scripts/locked-nixpkgs.sh")"
        export NIX_PATH
    fi

    while :; do
        local output=''
        if output="$(nix build --no-link --print-build-logs \
            --file "$repo_root" "$attr" 2>&1)"; then
            if [[ $round -gt 0 ]]; then
                log "${attr} builds after ${round} rewrite(s)"
            fi
            return 0
        fi

        local specified got
        specified="$(extract_hash 'specified|wanted' "$output")"
        got="$(extract_hash 'got' "$output")"

        if [[ -z "$specified" || -z "$got" ]]; then
            log "${attr} failed, and not on a hash mismatch:"
            printf '%s\n' "$output" >&2
            return 1
        fi

        if [[ "$specified" == "$got" ]]; then
            log "nix reported a mismatch of ${specified} against itself; refusing to loop"
            return 1
        fi

        round=$((round + 1))
        if [[ $round -gt $max_rounds ]]; then
            log "${attr} still disagrees after ${max_rounds} rewrite(s)"
            return 2
        fi

        log "round ${round}: ${specified} -> ${got}"
        rewrite_hash "$specified" "$got"
    done
}

main "$@"
