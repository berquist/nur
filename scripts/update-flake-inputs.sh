#!/usr/bin/env bash
#
# update-flake-inputs.sh — move flake.lock, check that the result still
# evaluates, and offer it as a pull request.
#
#   scripts/update-flake-inputs.sh                     every input, eval gate
#   scripts/update-flake-inputs.sh nixpkgs             one input
#   scripts/update-flake-inputs.sh --gate=full         the whole of nix flake check
#   scripts/update-flake-inputs.sh --deliver=pr
#
# This is the cheap half of the updater and the half that is complete on its
# own: no hashes to compute, no per-package policy, one changed file.  It is
# also what exercises the delivery path — runner, token, branch, signed commit,
# pull request — against a change that is trivial to review, which is why
# docs/version-updates.md §9 puts it first.
#
# ## The gate is not the same gate as CI's
#
# An input bump does **not** move what `just ci-matrix` tests.  The three matrix
# legs resolve `<nixpkgs>` from channel tarballs, not from flake.lock — see
# ./locked-nixpkgs.sh.  So this job and the package-version job cover genuinely
# different things and neither substitutes for the other.
#
# `nix flake check` is the real gate, and it needs **KVM** for the VM tests.  A
# hosted GitHub runner has none, so `--gate=eval` is the default: it forces the
# four evaluation checks and the flake's `packages`, which is what can honestly
# be claimed there.  Use `--gate=full` where KVM exists.
#
# Configuration for --deliver=pr is ./forge-pr.sh's; see its header.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

gate='eval'
deliver=none
dry_run=false
declare -a inputs=()

usage() {
    cat >&2 <<'EOF'
usage: update-flake-inputs.sh [OPTIONS] [INPUT...]

  --gate=MODE     eval (default) | full | none
  --deliver=MODE  none (default) | commit | pr
  --dry-run       with --deliver=pr, print the API calls without issuing them
  -h, --help      this

With no INPUT, every input is updated.
EOF
}

die() {
    printf 'update-flake-inputs: %s\n' "$1" >&2
    exit 1
}

log() {
    printf 'update-flake-inputs: %s\n' "$1" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gate=*) gate="${1#*=}" ;;
            --deliver=*) deliver="${1#*=}" ;;
            --dry-run) dry_run=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            -*) die "unknown option $1" ;;
            *) inputs+=("$1") ;;
        esac
        shift
    done

    case "$gate" in
        eval | full | none) ;;
        *) die '--gate must be eval, full or none' ;;
    esac

    case "$deliver" in
        none | commit | pr) ;;
        *) die '--deliver must be none, commit or pr' ;;
    esac
}

# The four checks that need no KVM, named rather than discovered: `nix flake
# check` has no "skip the VM tests" flag, and filtering by name at run time
# would silently drop a new eval check the day someone adds one.  Keep this in
# step with the `checks` block in ../flake.nix.
readonly -a eval_checks=(
    eval
    eval-aiida
    eval-cheminformatics
    eval-chemtools
)

run_gate() {
    local system
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"

    case "$gate" in
        none)
            log 'no gate, as asked'
            ;;
        eval)
            local -a targets=()
            local check
            for check in "${eval_checks[@]}"; do
                targets+=(".#checks.${system}.${check}")
            done
            log 'gating on the evaluation checks only (no KVM)'
            nix build --no-link --print-build-logs "${targets[@]}"
            ;;
        full)
            log 'gating on nix flake check, VM tests included'
            nix flake check --print-build-logs
            ;;
    esac
}

main() {
    parse_args "$@"
    cd "$repo_root"

    # Both sides hashed the same way, off the working tree: comparing against
    # the committed blob would call a lock that was already dirty "updated".
    local before after subject
    before="$(git -C "$repo_root" hash-object flake.lock)"

    if [[ ${#inputs[@]} -eq 0 ]]; then
        nix flake update
        subject='chore(deps): update flake inputs'
    else
        nix flake update "${inputs[@]}"
        subject="chore(deps): update flake input $(
            IFS=', '
            printf '%s' "${inputs[*]}"
        )"
    fi

    after="$(git -C "$repo_root" hash-object flake.lock)"
    if [[ "$before" == "$after" ]]; then
        log 'flake.lock did not move; nothing to do'
        return 0
    fi

    run_gate

    local body
    body="Automated flake input update, gated on \`--gate=${gate}\`.

Note that this does **not** move what \`just ci-matrix\` tests: those legs
resolve \`<nixpkgs>\` from channel tarballs rather than from \`flake.lock\`.
See \`scripts/locked-nixpkgs.sh\`."

    case "$deliver" in
        none)
            log 'flake.lock updated and left in the working tree'
            git -C "$repo_root" --no-pager diff --stat -- flake.lock
            ;;
        commit)
            git -C "$repo_root" add -- flake.lock
            git -C "$repo_root" commit --gpg-sign --message "$subject" \
                || die 'commit failed; if that is the signing key, use --deliver=none'
            ;;
        pr)
            local -a argv=(
                "${repo_root}/scripts/forge-pr.sh"
                --branch=update/flake-inputs
                --file=flake.lock
                "--message=${subject}"
                "--title=${subject}"
                "--body=${body}"
            )
            if [[ "$dry_run" == true ]]; then
                argv+=(--dry-run)
            fi
            "${argv[@]}"
            ;;
    esac
}

main "$@"
