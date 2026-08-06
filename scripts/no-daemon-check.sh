#!/usr/bin/env bash
#
# no-daemon-check.sh — everything that can be checked without a nix-daemon.
#
# The Claude Code sandbox blocks socket(AF_UNIX), so nix cannot reach the
# daemon and nothing can be built or realised.  Evaluation still works against
# a private chroot store, which is enough to catch module, overlay, package and
# test-script errors — most of what actually breaks here.
#
# Runs four checks:
#
#   1. every eval test in tests/qcarchive/, reported PASS/FAIL without building
#   2. instantiation of every VM test in tests/qcarchive/vm.nix
#   3. instantiation of every test in tests/dotdrop/
#   4. nix-instantiate --parse over every tracked .nix file
#
# The dotdrop tests are only *instantiated*, not run: unlike the qcarchive eval
# tests they do not bake their verdict into the build command — they are real
# runCommand builds that invoke the packaged binary, so there is nothing to
# read off without a daemon.  Instantiating still catches a broken overlay, a
# missing attribute or a syntax error in the test script.
#
# Everything is evaluated against the nixpkgs pinned in flake.lock, resolved to
# its store path without the network (see locked_nixpkgs below), so that what
# passes here is what `nix flake check` sees.
#
# Exits non-zero if any of them fails.  Safe to run outside the sandbox too:
# it only ever writes under $TMPDIR.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

: "${TMPDIR:=/tmp}"
store="$TMPDIR/no-daemon-check-store"

# ~/.cache is a read-only tmpfs in the sandbox, and /etc/nix/nixpkgs-config.nix
# lives outside the store, which restrict-eval will not accept.
export XDG_CACHE_HOME="$TMPDIR/no-daemon-check-cache"
export NIXPKGS_CONFIG=

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
# test — passes here and fails in `nix flake check`.  That is exactly how
# tests/qcarchive/vm.nix's compute-singlepoint slipped through.
#
# A flake input is added to the store as a fixed-output path (recursive
# sha256, name "source"), so its location is a pure function of the narHash
# already recorded in flake.lock: no network, no daemon, no `nix flake`
# command — which matters, since libgit2 in the sandbox refuses to open this
# repo at all ("unsupported extension name extensions.refstorage").
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

nixpkgs_origin=inherited
if [[ -z "${NIX_PATH:-}" || "$NIX_PATH" == *flake:* ]]; then
  if resolved=$(locked_nixpkgs); then
    nixpkgs_origin=flake.lock
  else
    registry=/etc/nix/registry.json
    if [[ -r $registry ]]; then
      resolved=$(jq -r '.flakes[] | select(.from.id == "nixpkgs") | .to.path // empty' "$registry" 2>/dev/null | head -1)
      nixpkgs_origin="flake registry — NOT the locked nixpkgs, so default-interpreter breakage will be missed"
    fi
  fi
  [[ -n ${resolved:-} ]] && export NIX_PATH="nixpkgs=$resolved"
fi
echo "NIX_PATH=${NIX_PATH:-<unset>} [$nixpkgs_origin]"

nix_eval() { nix-instantiate --store "$store" "$@"; }

failed=0
fail() {
  echo "  FAIL: $*"
  failed=1
}

# Psi4 comes from the nixos-qchem flake input, which is out of reach here.
# The compute tests only ever put it on the worker's PATH, so a stub is enough
# to instantiate them — this checks their module config and testScript, not
# that a real Psi4 builds.
# shellcheck disable=SC2016  # $out is Nix's, and must reach nix unexpanded
psi4_stub='(import <nixpkgs> { }).runCommand "psi4-stub" { } "mkdir -p $out/bin && touch $out/bin/psi4"'

# ---------------------------------------------------------------------------
echo
echo "=== qcarchive eval tests ==="
# Instantiate first.  This catches anything that throws outright, and it is
# also what seeds the chroot store: tests/qcarchive/default.nix reaches into
# <nixpkgs>/nixos/lib/eval-config.nix, and a bare `--eval` will not copy that
# source in — it fails with "path ... is not valid" until an instantiation has
# registered it.  The first run is slow for the same reason.
echo "  instantiating (first run copies nixpkgs into $store, and is slow) ..."
if ! nix_eval tests -A qcarchive.all >/dev/null 2>&1; then
  fail "tests -A qcarchive.all does not instantiate"
  nix_eval tests -A qcarchive.all 2>&1 | tail -15 | sed 's/^/      /'
fi

# Reported here rather than next to NIX_PATH above, because reading anything
# out of <nixpkgs> needs the store seeded first.  Worth a line: the whole
# python313 pin is about this number, and if it is not what flake.lock says,
# this run is not checking what CI checks.
default_python=$(nix_eval --eval --expr '(import <nixpkgs> { }).python3.version' 2>/dev/null | tr -d '"')
echo "  <nixpkgs> default python3 = ${default_python:-unknown}"

# check{} in tests/qcarchive/default.nix bakes the verdict into the
# derivation's build command, so the PASS/FAIL of every test is readable
# without building any of them.
results=$(
  # shellcheck disable=SC2016  # ${n} is Nix interpolation, not shell
  nix_eval --eval --strict --json -E '
    let
      t = (import ./tests { }).qcarchive;
      lib = (import <nixpkgs> { }).lib;
      names = builtins.filter (n: n != "all") (builtins.attrNames t);
    in
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = if lib.hasInfix "PASS:" t.${n}.buildCommand then "PASS" else "FAIL";
      }) names
    )' 2>/dev/null | tail -1
)

if [[ -z $results ]]; then
  fail "could not evaluate tests/qcarchive at all"
else
  jq -r 'to_entries[] | select(.value != "PASS") | "  FAIL: " + .key' <<<"$results"
  total=$(jq -r 'length' <<<"$results")
  passed=$(jq -r '[.[] | select(. == "PASS")] | length' <<<"$results")
  echo "  $passed/$total PASS"
  [[ $passed == "$total" ]] || failed=1
fi

# ---------------------------------------------------------------------------
echo
echo "=== VM tests instantiate ==="
# Instantiation forces the node module system and builds the Python test
# script, so a broken module or a syntax error in a testScript shows up here.
vm_names=$(nix_eval --eval --json --arg psi4 "$psi4_stub" \
  -E 'builtins.attrNames (import ./tests/qcarchive/vm.nix { })' 2>/dev/null | jq -r '.[]?')
for t in $vm_names; do
  if nix_eval tests/qcarchive/vm.nix -A "$t" --arg psi4 "$psi4_stub" >/dev/null 2>&1; then
    echo "  OK: $t"
  else
    fail "$t"
    nix_eval tests/qcarchive/vm.nix -A "$t" --arg psi4 "$psi4_stub" 2>&1 | tail -5 | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------------
echo
echo "=== dotdrop tests instantiate ==="
# Only instantiation: these are real builds that run the packaged binary, so
# there is no verdict to read without a daemon.  Instantiating them still
# forces the overlay, the derivation and the test scripts.
dd_names=$(nix_eval --eval --json \
  -E 'builtins.attrNames (import ./tests { }).dotdrop' 2>/dev/null | jq -r '.[]?')
if [[ -z $dd_names ]]; then
  fail "could not evaluate tests/dotdrop at all"
  nix_eval tests -A dotdrop.all 2>&1 | tail -15 | sed 's/^/      /'
fi
for t in $dd_names; do
  if nix_eval tests -A "dotdrop.$t" >/dev/null 2>&1; then
    echo "  OK: $t"
  else
    fail "dotdrop.$t"
    nix_eval tests -A "dotdrop.$t" 2>&1 | tail -5 | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------------
echo
echo "=== parse ==="
while IFS= read -r f; do
  nix-instantiate --parse "$f" >/dev/null 2>&1 || fail "$f"
done < <(git ls-files '*.nix')
echo "  $(git ls-files '*.nix' | wc -l) files"

# ---------------------------------------------------------------------------
echo
if [[ $failed -eq 0 ]]; then
  echo "all no-daemon checks passed"
else
  echo "FAILURES — see above"
fi
exit "$failed"
