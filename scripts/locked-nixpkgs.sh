#!/usr/bin/env bash
#
# locked-nixpkgs.sh — print a NIX_PATH pointing at the nixpkgs this flake locks.
#
# The value goes to stdout, so callers use it directly:
#
#   NIX_PATH=$(scripts/locked-nixpkgs.sh) && export NIX_PATH
#
# and a one-line note about where it came from goes to stderr, so it stays out
# of that assignment.  Run it on its own to see both.
#
# NIX_PATH normally points at flake:nixpkgs, which needs the network.  There
# are two ways to resolve it offline, and they are not interchangeable:
#
#   1. this flake's *own* locked nixpkgs — what `nix flake check` evaluates
#      against, and what CI sees;
#   2. the flake registry's pre-resolved nixpkgs — whatever the sandbox image
#      happens to carry.
#
# Prefer 1.  The registry copy trails the lock, and the gap is not cosmetic:
# with the registry at python3 = 3.13 and the lock at 3.14, everything that
# hinges on the default interpreter — the python313 pin, the meta.broken
# markings on the qcportal dependants, any `pkgs.python3.withPackages` in a
# test — passes locally and fails in `nix flake check`.  That is exactly how
# tests/qcarchive/vm.nix's compute-singlepoint slipped through.
#
# A flake input is added to the store as a fixed-output path (recursive
# sha256, name "source"), so its location is a pure function of the narHash
# already recorded in flake.lock: no network, no daemon, no `nix flake`
# command — which matters, since libgit2 in the sandbox refuses to open this
# repo at all ("unsupported extension name extensions.refstorage").
#
# An already-set NIX_PATH that does not mention a flake is passed through
# untouched, so setting it by hand still overrides everything here.
#
# Exits non-zero, having printed nothing to stdout, if it cannot resolve one at
# all — which is the caller's cue to stop rather than evaluate against whatever
# <nixpkgs> happens to mean.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

locked_nixpkgs() {
    local narhash base16 path
    narhash=$(jq -r '.nodes.nixpkgs.locked.narHash // empty' flake.lock 2>/dev/null)
    [[ $narhash == sha256-* ]] || return 1
    base16=$(nix-hash --to-base16 --type sha256 "${narhash#sha256-}" 2>/dev/null) || return 1
    path=$(nix-store --print-fixed-path --recursive sha256 "$base16" source 2>/dev/null) || return 1
    # Only usable if the input has actually been fetched at some point.
    [[ -d $path ]] || return 1
    printf '%s\n' "$path"
}

registry_nixpkgs() {
    local registry=/etc/nix/registry.json path
    [[ -r $registry ]] || return 1
    path=$(jq -r '.flakes[] | select(.from.id == "nixpkgs") | .to.path // empty' \
        "$registry" 2>/dev/null | head -1)
    [[ -n $path ]] || return 1
    printf '%s\n' "$path"
}

if [[ -n "${NIX_PATH:-}" && "$NIX_PATH" != *flake:* ]]; then
    echo "NIX_PATH=$NIX_PATH [inherited]" >&2
    printf '%s\n' "$NIX_PATH"
    exit 0
fi

if resolved=$(locked_nixpkgs); then
    origin=flake.lock
elif resolved=$(registry_nixpkgs); then
    origin="flake registry — NOT the locked nixpkgs, so default-interpreter breakage will be missed"
else
    echo "locked-nixpkgs.sh: no nixpkgs found in flake.lock or the registry" >&2
    exit 1
fi

echo "NIX_PATH=nixpkgs=$resolved [$origin]" >&2
printf 'nixpkgs=%s\n' "$resolved"
