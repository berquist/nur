#!/usr/bin/env bash
#
# Regroup a `nix build -L` log so each derivation's output is contiguous.
#
# `--keep-going` builds many derivations at once and nix interleaves their
# output line by line, so a 4000-line log is 12 builds shuffled together and
# no single failure can be read straight through.  Every builder line carries
# its derivation name as a `name> ` prefix, though, which is enough to undo
# the interleaving exactly: bucket by prefix, then replay each bucket in the
# order its lines first appeared.
#
# Lines with no prefix are nix's own — the build plan, `building '...'`, and
# the `error: builder for ... failed` blocks with their last-25-lines excerpt.
# Those go to a section of their own, emitted first, which makes it the
# summary of what failed.
#
# Usage:
#   scripts/demux-build-log.sh [-l|-o NAME] [FILE]
#
#   (no flag)   table of contents, then every section in full
#   -l          table of contents only
#   -o NAME     one section's lines, unprefixed and with no header; NAME may
#               be a substring, so `-o postopus` finds python3.13-postopus
#
# FILE defaults to stdin.

set -euo pipefail

readonly NIX_SECTION='(nix)'

# A store-path name, which is what nix puts before the `> `.  Deliberately
# narrower than "anything without a space": `just ci-matrix` echoes
# `==> nixpkgs-unstable` and `ci-eval`'s --xml output ends elements with
# `</items>`, and both would otherwise be read as derivation prefixes and
# become sections of their own.
#
# The `>` is written bare.  Escaping it would be right in a literal inside
# [[ ]], but this is a variable, and regcomp reads `\>` as GNU's end-of-word
# anchor — which matches after `error`, `warning` and `building`, turning
# every nix diagnostic into a section of its own.
readonly PREFIX_RE='^([A-Za-z0-9][A-Za-z0-9._+-]*)> ?(.*)$'

usage() {
    cat <<'EOF'
usage: demux-build-log.sh [-l] [-o NAME] [FILE]

  -l, --list      list the sections found, with line counts
  -o, --only NAME print only the section whose name contains NAME
  -h, --help      this message

FILE defaults to stdin.
EOF
}

mode=full
only=

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l | --list)
            mode=list
            shift
            ;;
        -o | --only)
            [[ $# -ge 2 ]] || {
                echo "demux-build-log.sh: --only needs a name" >&2
                exit 2
            }
            mode=only
            only=$2
            shift 2
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
            echo "demux-build-log.sh: unknown option $1" >&2
            usage >&2
            exit 2
            ;;
        *) break ;;
    esac
done

[[ $# -le 1 ]] || {
    echo "demux-build-log.sh: at most one FILE" >&2
    exit 2
}

# Buckets live in files rather than in shell strings: appending to a bash
# variable is quadratic in the log size, and these logs run to megabytes.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

declare -a order=()
declare -A slot=()
declare -A count=()

next=0

# Registration is inline rather than in a helper: a helper would have to hand
# the path back through $(...), and a command substitution is a subshell, so
# every update to slot/order/next would be discarded the moment it returned.
while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $PREFIX_RE ]]; then
        name=${BASH_REMATCH[1]}
        rest=${BASH_REMATCH[2]}
    else
        name=$NIX_SECTION
        rest=$line
    fi
    if [[ -z ${slot[$name]+set} ]]; then
        slot[$name]=$next
        count[$name]=0
        order+=("$name")
        next=$((next + 1))
    fi
    printf '%s\n' "$rest" >>"$workdir/${slot[$name]}"
    count[$name]=$((count[$name] + 1))
done <"${1:-/dev/stdin}"

[[ ${#order[@]} -gt 0 ]] || exit 0

# The nix section is the build plan and the failure summary, so it leads even
# though it is rarely the first line seen.
declare -a sections=()
if [[ -n ${slot[$NIX_SECTION]+set} ]]; then
    sections+=("$NIX_SECTION")
fi
for name in "${order[@]}"; do
    [[ $name == "$NIX_SECTION" ]] || sections+=("$name")
done

if [[ $mode == only ]]; then
    found=
    for name in "${sections[@]}"; do
        if [[ $name == *"$only"* ]]; then
            cat "$workdir/${slot[$name]}"
            found=yes
        fi
    done
    [[ -n $found ]] || {
        echo "demux-build-log.sh: no section matching '$only'" >&2
        exit 1
    }
    exit 0
fi

for name in "${sections[@]}"; do
    printf '%8d  %s\n' "${count[$name]}" "$name"
done

[[ $mode == list ]] && exit 0

for name in "${sections[@]}"; do
    printf '\n========== %s  (%d lines) ==========\n' "$name" "${count[$name]}"
    cat "$workdir/${slot[$name]}"
done
