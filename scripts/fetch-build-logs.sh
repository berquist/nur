#!/usr/bin/env bash
#
# Pull every build log a failed `nix build` pointed at, one file per package.
#
# A `--keep-going` run that loses a dozen derivations ends with a dozen lines
# like
#
#   For full logs, run:
#     nix log /nix/store/ziqxz1…-python3.13-aiida-lammps-1.0.2-unstable-2025-01-07.drv
#
# and each of those is a separate command to type, with a 32-character hash in
# it that cannot be typed from memory.  This runs them all and writes each one
# to a `log-` file, which is the shape the rest of this repo's workflow already
# uses — see ./demux-build-log.sh, which reads the same files.
#
# The filename is the derivation's own name with its hash moved from the front
# to the back:
#
#   /nix/store/ziqxz1…-python3.13-aiida-lammps-1.0.2-unstable-2025-01-07.drv
#   log-python3.13-aiida-lammps-1.0.2-unstable-2025-01-07-ziqxz1…
#
# Same three parts, reordered so the useful one is first.  A store path sorts
# and tab-completes by its hash, which is noise; this sorts by package, so a
# directory of them groups by family and `log-python3.13-aiida-<TAB>` narrows to
# what you meant.  Keeping the version and the hash is what makes each file
# distinct: two builds of one package — a rebuild after a fix, or the same
# package on two channels — land side by side rather than one overwriting the
# other, and the hash is the only part guaranteed to tell them apart.
#
# Usage:
#   scripts/fetch-build-logs.sh [-n] [-o DIR] [FILE...]
#
#   -n          print the commands instead of running them
#   -o DIR      write the logs here (default: the working directory)
#
# FILE defaults to stdin, so this reads a pipe as happily as a saved log:
#
#   just ci-build 2>&1 | tee build.log
#   scripts/fetch-build-logs.sh build.log
#
# Needs a nix-daemon: `nix log` reads the store.

set -euo pipefail

# The `.drv` path out of a `nix log` line, wherever it sits on that line.  nix
# indents it under "For full logs, run:" and colours the surrounding text, so
# anchoring at the start of the line would find nothing.
#
# The hash length is written out rather than left as `+`: every store path has
# exactly 32 base32 characters, and being strict is what keeps a line that
# merely mentions a path in prose from being collected.
readonly DRV_RE='nix log (/nix/store/[0-9a-z]{32}-[^[:space:]]+\.drv)'

dry_run=false
out_dir=.

die() {
    printf 'fetch-build-logs: %s\n' "$1" >&2
    exit 1
}

log() {
    printf 'fetch-build-logs: %s\n' "$1" >&2
}

usage() {
    sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

# `<name>-<hash>` from a store path: the basename with `.drv` dropped and the
# hash moved to the end.  Nothing is discarded, so two store paths can never
# produce one filename — which is why there is no collision handling below.
#
# The two expansions split on the *first* hyphen, which is always the one after
# the hash: a store hash is 32 base32 characters and base32 has no hyphen in it.
log_name_of() {
    local base="${1##*/}"
    base="${base%.drv}"

    printf '%s-%s' "${base#*-}" "${base%%-*}"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n) dry_run=true ;;
            -o)
                [[ $# -ge 2 ]] || die '-o needs a directory'
                out_dir="$2"
                shift
                ;;
            -o*) out_dir="${1#-o}" ;;
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*) die "unknown option $1" ;;
            *) break ;;
        esac
        shift
    done

    command -v nix >/dev/null || die 'nix is not on PATH'
    [[ -d "$out_dir" ]] || die "no such directory: ${out_dir}"

    # Deduplicated, in the order nix first mentioned them.  A `--keep-going`
    # summary repeats the same path in its per-derivation error and again in
    # the closing list, and fetching a log twice is only slower, not wrong.
    local -a drvs=()
    mapfile -t drvs < <(
        grep --extended-regexp --only-matching --no-filename -- "$DRV_RE" "$@" \
            | awk '{ print $NF }' \
            | awk '!seen[$0]++'
    )

    if [[ ${#drvs[@]} -eq 0 ]]; then
        log 'no nix log lines found'
        return 0
    fi

    log "${#drvs[@]} derivation(s) to fetch"

    local drv dest failed=0

    for drv in "${drvs[@]}"; do
        dest="${out_dir%/}/log-$(log_name_of "$drv")"

        if [[ "$dry_run" == true ]]; then
            printf 'nix log %s > %s\n' "$drv" "$dest"
            continue
        fi

        # Not `>` at the call site: a derivation nix has no log for would
        # otherwise leave an empty file behind, which reads exactly like a
        # build that produced no output.
        if nix log "$drv" >"${dest}.part" 2>/dev/null; then
            mv -- "${dest}.part" "$dest"
            log "wrote ${dest} ($(wc --lines <"$dest") lines)"
        else
            rm --force -- "${dest}.part"
            log "no log available for ${drv}"
            failed=$((failed + 1))
        fi
    done

    [[ "$failed" -eq 0 ]] || die "${failed} derivation(s) had no log"
}

main "$@"
