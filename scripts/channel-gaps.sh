#!/usr/bin/env bash
#
# channel-gaps.sh — find, in one run, every attribute of this repository that
# will not evaluate on a given nixpkgs channel.
#
# The failure this exists for is `callPackage` meeting an undefaulted argument
# the channel does not have.  It `abort`s, and an abort is not a value: it
# cannot be caught by `builtins.tryEval`, it cannot be marked `meta.broken`
# (there is no package left to mark), and it takes down the *whole* evaluation
# rather than the one attribute.  `just ci-eval` therefore reports exactly one
# offender per run, whichever it reached first, and finding three of them costs
# three CI rounds.  That is not hypothetical: nixos-26.05 had `deepmd-kit`
# (e3nn), `sevenn` (e3nn and matscipy) and `tensorpotential` (matscipy), and
# the log named only the first.
#
# So each attribute is forced in its own `nix-instantiate` process.  An abort
# then kills that process alone, and every offender is reported.  It costs one
# nixpkgs evaluation per attribute — about 200 — which is why they run in
# parallel.  Against a `ci-build` round that takes twenty minutes to tell you
# less, that is a good trade.
#
# Exactness is why it forces attributes rather than reading
# `builtins.functionArgs` and comparing names against the channel.  The name
# comparison is much faster and it is wrong in both directions: it reports
# ../pkgs/chemfiles-python's `chemfilesLib` and ../pkgs/molara's `mesaDrivers`
# as gaps, when ../overlays passes both explicitly, and it sees nothing at all
# of a failure that is not about a missing argument.
#
# **It does not catch a dependency that is present but too old.**  A version
# floor is checked by `pythonRuntimeDepsCheckHook` during the build, long after
# evaluation has succeeded: nixos-26.05 carries warp-lang 1.11.0 against
# ../pkgs/nvalchemi-toolkit-ops' `>= 1.13.0`, and this script is happy with it.
# A gate written for a channel wants the floor as well as the name — see the
# `nvalchemi-toolkit-ops` binding in ../overlays/default.nix.
#
# Usage:
#
#   ./scripts/channel-gaps.sh                       # every channel in the matrix
#   ./scripts/channel-gaps.sh nixos-26.05           # one of them
#   ./scripts/channel-gaps.sh /nix/store/xxx-source # a nixpkgs already unpacked
#
# The third form is the one to reach for after a failed CI run, which leaves
# that channel's nixpkgs in the store: it is the exact tree that failed, it
# needs no network, and — being a local path — it evaluates against
# `--store dummy://`, so it works with no nix-daemon and from inside the Claude
# Code sandbox.  A channel *name* has to be fetched, so that form needs a real
# store and a network.
#
# Exits non-zero if any attribute failed to evaluate.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Keep in step with `channels` in ../Justfile, which mirrors the nixPath matrix
# in ../.github/workflows/build.yml.
default_channels=(nixpkgs-unstable nixos-unstable nixos-26.05)
nixpkgs_url="https://github.com/NixOS/nixpkgs/archive/refs/heads"

jobs=${CHANNEL_GAPS_JOBS:-$(nproc 2>/dev/null || echo 4)}

channels=("$@")
if [[ ${#channels[@]} -eq 0 ]]; then
    channels=("${default_channels[@]}")
fi

# The *last* `error:` line carrying text, which is where nix puts the thing that
# actually went wrong.  It opens with a bare `error:`, spends thirty lines on a
# stack trace, and only then says
#
#   error: evaluation aborted with the following error message:
#   'lib.customisation.callPackageWith: Function called without required
#   argument "e3nn" at pkgs/deepmd-kit/default.nix:34 ...'
#
# which names the package, the argument and the line.  Taking the first match
# instead gives the bare `error:`, and taking the last line gives whichever
# trace frame was printed last -- here, a frame inside channel-gaps.nix, which
# is the least useful answer available.  scripts/no-daemon-check.sh leads with
# the first match for the opposite reason: its failures are broken-package
# reports, where the boilerplate comes after rather than before.
# shellcheck disable=SC2329
# Reached only through `export -f` and the `bash -c` below, which shellcheck
# cannot follow.
last_error() {
    local log=$1
    if grep -E 'error: .' "$log" | tail -n 1 | grep -q .; then
        grep -E 'error: .' "$log" | tail -n 1
        return
    fi
    tail -n 1 "$log"
}

# shellcheck disable=SC2329
# Likewise: invoked by xargs, one process per attribute, which is the whole
# point — see the header.
probe_one() {
    local attr=$1 log
    log=$(mktemp "${TMPDIR:-/tmp}/channel-gaps.XXXXXX")

    # shellcheck disable=SC2086
    # store_opt is deliberately word-split: it is either empty or the two words
    # `--store dummy://`, and quoting it would pass an empty argument to nix.
    if nix-instantiate --eval --strict $store_opt \
        --argstr attr "$attr" scripts/channel-gaps.nix >/dev/null 2>"$log"; then
        rm -f "$log"
        return 0
    fi

    printf '  FAIL %s\n' "$attr"
    last_error "$log" | sed 's/^/       /'
    rm -f "$log"
    return 1
}

export -f probe_one last_error

status=0

for channel in "${channels[@]}"; do
    # A path is taken as written and can be evaluated with no store; anything
    # else is a channel name and becomes the branch tarball, the same URL
    # `just ci CHANNEL` uses, which has to be fetched into a real one.
    if [[ -e $channel ]]; then
        nixpkgs=$channel
        store_opt="--store dummy://"
    else
        nixpkgs="${nixpkgs_url}/${channel}.tar.gz"
        store_opt=""
    fi

    export NIX_PATH="nixpkgs=${nixpkgs}"
    export store_opt

    printf '==> %s\n' "$channel"
    printf '    %s\n' "$nixpkgs"

    # `--arg attr null` is the default the file already declares, and passing it
    # is not redundant: `nix-instantiate --eval` auto-calls a function only when
    # it is given at least one argument, and prints `<LAMBDA>` otherwise.
    mapfile -t targets < <(
        # shellcheck disable=SC2086
        nix-instantiate --eval $store_opt --arg attr null scripts/channel-gaps.nix 2>/dev/null |
            sed -e 's/^"//' -e 's/"$//' -e 's/\\n/\n/g'
    )

    if [[ ${#targets[@]} -eq 0 ]]; then
        printf '  FAIL could not list attributes; the channel itself may not evaluate\n'
        status=1
        continue
    fi

    printf '    %d attributes, %d at a time\n' "${#targets[@]}" "$jobs"

    if printf '%s\n' "${targets[@]}" |
        xargs -P "$jobs" -I {} bash -c 'probe_one "$@"' _ {}; then
        printf '    OK\n'
    else
        status=1
    fi
done

if [[ $status -eq 0 ]]; then
    printf '\nevery attribute evaluates on every channel checked\n'
else
    printf '\nsome attributes do not evaluate; see the FAIL lines above\n'
fi

exit "$status"
