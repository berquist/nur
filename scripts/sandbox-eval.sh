#!/usr/bin/env bash
#
# sandbox-eval.sh — evaluate one Nix expression with no nix-daemon.
#
# The Claude Code sandbox blocks socket(AF_UNIX), so nix cannot reach the
# daemon: nothing builds, nothing instantiates, and `nix eval` fails before it
# starts.  Evaluation against `--store dummy://` still works, which answers most
# of the questions worth asking about a derivation while writing it — what a
# version string came out as, whether an attribute exists, what a list of
# makeWrapperArgs actually contains, which python the overlay resolved.
#
# scripts/no-daemon-check.sh covers the whole test suite; this is the one-off.
#
# Two forms, told apart by whether the argument is a bare attribute path:
#
#   ./scripts/sandbox-eval.sh shakenbreak.version
#   ./scripts/sandbox-eval.sh 'builtins.attrNames (import ./. { })'
#
# The first is shorthand for `(import ./. { }).shakenbreak.version`, this repo
# being what one usually wants to ask about.  Anything containing a space, a
# bracket or a quote is passed to nix verbatim, so the second form reaches
# <nixpkgs> and everything else.
#
# --json for a value a later pipe has to read; the default is nix's own syntax.
#
# Prints the value on stdout and everything else on stderr, so this composes:
#
#   ./scripts/sandbox-eval.sh --json 'builtins.attrNames (import ./. { })' | jq length
#
# Exits with nix's own status, so a failed evaluation fails the script.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

usage() {
    cat >&2 <<'EOF'
usage: sandbox-eval.sh [--json] [--no-strict] <attr-path | nix-expression>

  sandbox-eval.sh vise.version
  sandbox-eval.sh shakenbreak.makeWrapperArgs
  sandbox-eval.sh --json 'builtins.attrNames (import ./. { })'
  sandbox-eval.sh '(import <nixpkgs> { }).python3.version'

A bare attribute path is resolved against this repo's default.nix.  Anything
else is handed to nix as written.
EOF
}

json=()
# --strict by default: without it a list or attrset prints as <CODE> and the
# answer to "what is in this list" is nothing at all.
strict=(--strict)

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            json=(--json)
            shift
            ;;
        --no-strict)
            strict=()
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "sandbox-eval.sh: unknown option $1" >&2
            usage
            exit 2
            ;;
        *) break ;;
    esac
done

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

expr=$1

# A bare attribute path — letters, digits, dashes and dots, nothing else — is
# the shorthand.  Everything a real expression needs (spaces, parens, quotes,
# `import`) falls outside that character class, so there is no expression this
# misreads as a path.
if [[ $expr =~ ^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)*$ ]]; then
    expr="(import ./. { }).$expr"
    echo "expr: $expr" >&2
fi

: "${TMPDIR:=/tmp}"
# ~/.cache is a read-only tmpfs in the sandbox, and /etc/nix/nixpkgs-config.nix
# lives outside the store, which restrict-eval will not accept.
export XDG_CACHE_HOME="$TMPDIR/sandbox-eval-cache"
export NIXPKGS_CONFIG=

# Reports which nixpkgs it picked, and why it matters, on stderr.
NIX_PATH=$("$(dirname "${BASH_SOURCE[0]}")/locked-nixpkgs.sh")
export NIX_PATH

# dummy:// rather than a chroot store: this only ever evaluates, and a chroot
# store would have to be seeded by an instantiation first — see the note in
# scripts/no-daemon-check.sh about `path ... is not valid`.
exec nix-instantiate --eval "${strict[@]}" "${json[@]}" --store dummy:// -E "$expr"
