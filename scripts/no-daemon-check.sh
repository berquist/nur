#!/usr/bin/env bash
#
# no-daemon-check.sh — everything that can be checked without a nix-daemon.
#
# The Claude Code sandbox blocks socket(AF_UNIX), so nix cannot reach the
# daemon and nothing can be built or realised.  Evaluation still works against
# a private chroot store, which is enough to catch module, overlay, package and
# test-script errors — most of what actually breaks here.
#
# Runs three checks:
#
#   1. every eval test in tests/, reported PASS/FAIL without building
#   2. instantiation of every VM test in tests/vm.nix
#   3. nix-instantiate --parse over every tracked .nix file
#
# Exits non-zero if any of them fails.  Safe to run outside the sandbox too:
# it only ever writes under $TMPDIR.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${TMPDIR:=/tmp}"
store="$TMPDIR/no-daemon-check-store"

# ~/.cache is a read-only tmpfs in the sandbox, and /etc/nix/nixpkgs-config.nix
# lives outside the store, which restrict-eval will not accept.
export XDG_CACHE_HOME="$TMPDIR/no-daemon-check-cache"
export NIXPKGS_CONFIG=

# NIX_PATH normally points at flake:nixpkgs, which needs the network.  The
# flake registry has already resolved it to a store path; reuse that.
if [[ -z "${NIX_PATH:-}" || "$NIX_PATH" == *flake:* ]]; then
  registry=/etc/nix/registry.json
  if [[ -r $registry ]]; then
    resolved=$(jq -r '.flakes[] | select(.from.id == "nixpkgs") | .to.path // empty' "$registry" 2>/dev/null | head -1)
    [[ -n ${resolved:-} ]] && export NIX_PATH="nixpkgs=$resolved"
  fi
fi
echo "NIX_PATH=${NIX_PATH:-<unset>}"

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
psi4_stub='(import <nixpkgs> { }).runCommand "psi4-stub" { } "mkdir -p $out/bin && touch $out/bin/psi4"'

# ---------------------------------------------------------------------------
echo
echo "=== eval tests ==="
# Instantiate first.  This catches anything that throws outright, and it is
# also what seeds the chroot store: tests/default.nix reaches into
# <nixpkgs>/nixos/lib/eval-config.nix, and a bare `--eval` will not copy that
# source in — it fails with "path ... is not valid" until an instantiation has
# registered it.  The first run is slow for the same reason.
echo "  instantiating (first run copies nixpkgs into $store, and is slow) ..."
if ! nix_eval tests -A all >/dev/null 2>&1; then
  fail "tests -A all does not instantiate"
  nix_eval tests -A all 2>&1 | tail -15 | sed 's/^/      /'
fi

# check{} in tests/default.nix bakes the verdict into the derivation's build
# command, so the PASS/FAIL of every test is readable without building any of
# them.
results=$(
  nix_eval --eval --strict --json -E '
    let
      t = import ./tests { };
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
  fail "could not evaluate tests/ at all"
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
  -E 'builtins.attrNames (import ./tests/vm.nix { })' 2>/dev/null | jq -r '.[]?')
for t in $vm_names; do
  if nix_eval tests/vm.nix -A "$t" --arg psi4 "$psi4_stub" >/dev/null 2>&1; then
    echo "  OK: $t"
  else
    fail "$t"
    nix_eval tests/vm.nix -A "$t" --arg psi4 "$psi4_stub" 2>&1 | tail -5 | sed 's/^/      /'
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
