#!/usr/bin/env bash
#
# update-packages.sh — run nix-update over the packages this repository defines,
# honouring the policy in ./update-universe.nix.
#
#   scripts/update-packages.sh --scan                 what would move, nothing written
#   scripts/update-packages.sh --scan qcportal        one package
#   scripts/update-packages.sh qcportal               rewrite, fix hashes, build
#   scripts/update-packages.sh --deliver=pr --limit=5
#
# Everything the scheduled workflow does goes through this script, and the
# workflow calls the `just` recipe that calls it.  There is deliberately no
# logic that exists only in CI — see ../Justfile, which has the same arrangement
# with the ci-* recipes.
#
# ## Scan mode restores the tree rather than working in a worktree
#
# nix-update has no dry run: it always rewrites the file.  The obvious way to
# get one is a throwaway "git worktree", and that is wrong here for two reasons.
# A worktree is checked out from a commit, so it would not see the
# passthru.updatePolicy annotations while they are still uncommitted — the exact
# situation in which someone runs a scan.  And flake evaluation ignores
# untracked files, so a newly added package would be invisible.  Snapshotting
# the one file nix-update touches and putting it back is simpler, sees the
# working tree as it is, and happens on every path out of process_one().
#
# ## What the build gate is worth here
#
# --build is not a formality.  The check phases in this repository are large and
# load-bearing, so building aiida-core after a bump runs its whole suite — a far
# stronger signal than a hash comparison, and also why a full run is hours of
# work and belongs on a machine that can afford it.  A failed build is
# information: the report records it and no pull request is opened.
#
# Needs a nix-daemon and the network.  --policy is the one mode that does not.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly universe_expr="${repo_root}/scripts/update-universe.nix"

scan=false
deliver=none
dry_run=false
build=true
limit=0
json_out=''
policy_only=false
policy=''
report=''
snapshot=''
snapshot_target=''
keep_changes=false
declare -a selected=()

usage() {
    cat >&2 <<'EOF'
usage: update-packages.sh [OPTIONS] [ATTR...]

  --scan              report what would move, then restore the tree
  --deliver=MODE      none (default) | commit | pr
  --limit=N           stop after N packages have actually changed (0 = no limit)
  --no-build          skip the build gate; scan mode never builds anyway
  --dry-run           with --deliver=pr, print the API calls without issuing them
  --json=PATH         write the machine-readable report here
  --policy            print the resolved policy as JSON and exit
  -h, --help          this

With no ATTR, every package whose policy makes it actionable is attempted.
EOF
}

die() {
    printf 'update-packages: %s\n' "$1" >&2
    exit 1
}

log() {
    printf 'update-packages: %s\n' "$1" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scan) scan=true ;;
            --deliver=*) deliver="${1#*=}" ;;
            --limit=*) limit="${1#*=}" ;;
            --json=*) json_out="${1#*=}" ;;
            --no-build) build=false ;;
            --dry-run) dry_run=true ;;
            --policy) policy_only=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            -*) die "unknown option $1" ;;
            *) selected+=("$1") ;;
        esac
        shift
    done

    case "$deliver" in
        none | commit | pr) ;;
        *) die '--deliver must be none, commit or pr' ;;
    esac

    if [[ "$scan" == true ]]; then
        build=false
        [[ "$deliver" == none ]] \
            || die "--scan writes nothing, so --deliver=${deliver} cannot mean anything"
    fi

    [[ "$limit" =~ ^[0-9]+$ ]] || die '--limit takes a number'
}

# nix-update is in the devShell, not on a bare PATH, and this script is written
# against the flags 1.16.0 documents.  Checking them here turns "the flag was
# renamed" from a silent no-op three hundred packages deep into one line before
# any work starts.
require_tools() {
    command -v nix >/dev/null || die 'nix is not on PATH'
    command -v jq >/dev/null || die 'jq is not on PATH; run inside the devShell'

    if [[ "$policy_only" == true ]]; then
        return
    fi

    command -v nix-update >/dev/null \
        || die 'nix-update is not on PATH; run inside the devShell'

    local help flag
    help="$(nix-update --help 2>&1 || true)"
    for flag in --flake --build --version; do
        grep --quiet --fixed-strings -- "$flag" <<<"$help" \
            || die "nix-update does not advertise ${flag}; re-read its --help before trusting this script"
    done
}

# The locked nixpkgs rather than the ambient one, for the same reason
# ./locked-nixpkgs.sh exists: a policy computed against whatever the registry
# happens to hold is a policy for a different package set.
#
# nix-instantiate against `--store dummy://` rather than `nix eval`, which is
# the same trick ./sandbox-eval.sh uses and gives the same property: resolving
# the policy needs no nix-daemon.  That is what lets `--policy` answer inside a
# sandbox that has none, and it costs nothing anywhere else — this only ever
# evaluates metadata.
#
# When packages were named on the command line they are passed through as
# `only`, which is the difference between seconds and minutes: resolving the
# whole universe forces `lib.isDerivation` over every top-level attribute, and
# that is an evaluation of the entire overlaid package set.  `just update-scan
# qcportal` has no business paying for it.
resolve_policy() {
    local nix_path only='[ ]'

    if [[ ${#selected[@]} -gt 0 ]]; then
        only="[ $(printf '"%s" ' "${selected[@]}")]"
    fi

    nix_path="$("${repo_root}/scripts/locked-nixpkgs.sh")"
    # `--expr 'import … { }'` rather than `--file`: nix-instantiate hands a
    # file's value back as-is, and this one is a function, so it has to be
    # applied here for its `pkgs ? import <nixpkgs> { }` default to fire.
    NIX_PATH="$nix_path" nix-instantiate \
        --eval --strict --json --store dummy:// \
        --expr "import ${universe_expr} { only = ${only}; }"
}

field_of() {
    jq --raw-output --arg a "$1" --arg f "$2" '.packages[$a][$f] // ""' <<<"$policy"
}

# "X.Y.Z-unstable-YYYY-MM-DD" -> "YYYY-MM-DD", empty for anything else.
unstable_date() {
    grep --extended-regexp --only-matching -- '-unstable-[0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$1" \
        | sed 's/^-unstable-//' \
        || true
}

nix_update_argv() {
    local attr="$1" mode="$2" branch="$3"
    local -a argv=(nix-update --flake)

    case "$mode" in
        branch)
            if [[ -n "$branch" ]]; then
                argv+=("--version=branch=${branch}")
            else
                argv+=(--version=branch)
            fi
            ;;
        stable) ;;
        *) die "nix_update_argv called for mode ${mode}" ;;
    esac

    if [[ "$build" == true ]]; then
        argv+=(--build)
    fi

    argv+=("$attr")
    printf '%s\n' "${argv[@]}"
}

# A secondary source whose rev is pinned by a file inside the *new* upstream
# tree — ../pkgs/chemfiles' testsDataRev, read out of tests/CMakeLists.txt.
# Generic on purpose: "upstream pins its own test data" is a recurring shape,
# and the alternative is calling the package manual forever.
apply_rev_from() {
    local attr="$1" file="$2" spec="$3"
    local src_file pattern binding source_path new_rev

    src_file="$(jq --raw-output '.file' <<<"$spec")"
    pattern="$(jq --raw-output '.pattern' <<<"$spec")"
    binding="$(jq --raw-output '.binding' <<<"$spec")"

    source_path="$(
        cd "$repo_root" && nix build --no-link --print-out-paths ".#${attr}.src" 2>/dev/null
    )" || {
        log "${attr}: could not realise the new src to read ${src_file}"
        return 1
    }

    [[ -r "${source_path}/${src_file}" ]] || {
        log "${attr}: ${src_file} is not in the new source"
        return 1
    }

    new_rev="$(
        grep --extended-regexp --only-matching --max-count=1 -- "$pattern" \
            "${source_path}/${src_file}" \
            | grep --extended-regexp --only-matching --max-count=1 -- '[0-9a-f]{7,40}'
    )" || {
        log "${attr}: ${src_file} has no match for ${pattern}"
        return 1
    }

    python3 - "${repo_root}/${file}" "$binding" "$new_rev" <<'PY'
import pathlib
import re
import sys

path, binding, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
pattern = re.compile(r'(\b' + re.escape(binding) + r'\s*=\s*")[^"]*(")')
updated, count = pattern.subn(lambda m: m.group(1) + value + m.group(2), text, count=1)
if count != 1:
    sys.exit(f"{path}: no binding named {binding}")
path.write_text(updated)
PY

    log "${attr}: ${binding} -> ${new_rev}"
}

handle_secondaries() {
    local attr="$1" file="$2"
    local secondary count index entry mode name reason rev_from

    secondary="$(jq --compact-output --arg a "$attr" '.packages[$a].secondary // []' <<<"$policy")"
    count="$(jq 'length' <<<"$secondary")"
    [[ "$count" -gt 0 ]] || return 0

    for ((index = 0; index < count; index++)); do
        entry="$(jq --compact-output --argjson i "$index" '.[$i]' <<<"$secondary")"
        mode="$(jq --raw-output '.mode' <<<"$entry")"
        name="$(jq --raw-output '.name' <<<"$entry")"
        reason="$(jq --raw-output '.reason // ""' <<<"$entry")"

        case "$mode" in
            pinned)
                log "${attr}: leaving secondary ${name} alone -- ${reason}"
                ;;
            derived)
                rev_from="$(jq --compact-output '.revFrom // empty' <<<"$entry")"
                if [[ -n "$rev_from" ]]; then
                    apply_rev_from "$attr" "$file" "$rev_from" || return 1
                fi
                "${repo_root}/scripts/refresh-hashes.sh" "$attr" || return 1
                ;;
            *)
                log "${attr}: unknown secondary mode ${mode}"
                return 1
                ;;
        esac
    done
}

# nixfmt and the hooks, because a rewritten `version` line can leave a file
# nixfmt would change, and a pull request that fails the repository's own hooks
# wastes the reviewer's time.  Best effort: neither tool is on a bare PATH, and
# a missing formatter is not a reason to drop a good bump.
tidy() {
    local file="$1"

    if command -v nixfmt >/dev/null; then
        nixfmt "${repo_root}/${file}" >/dev/null 2>&1 || true
    fi

    if command -v prek >/dev/null; then
        (cd "$repo_root" && prek run --files "$file") >/dev/null 2>&1 || true
    fi
}

commit_locally() {
    local attr="$1" file="$2" old="$3" new="$4"

    git -C "$repo_root" add -- "$file"
    # --gpg-sign with no fallback: commits here are signed, and a bot that
    # quietly produces unsigned ones is worse than one that stops.  The
    # unattended path does not come through here at all — it goes through
    # ./forge-pr.sh, where the forge signs.
    git -C "$repo_root" commit --gpg-sign \
        --message "chore(deps): update ${attr} to ${new}" \
        --message "${old} -> ${new}" \
        || die 'commit failed; if that is the signing key, use --deliver=none and commit by hand'
}

open_pull_request() {
    local attr="$1" file="$2" old="$3" new="$4"
    local -a argv=(
        "${repo_root}/scripts/forge-pr.sh"
        "--branch=update/${attr}"
        "--file=${file}"
        "--message=chore(deps): update ${attr} to ${new}"
        "--title=chore(deps): update ${attr} to ${new}"
        "--body=Automated version bump of ${attr}, ${old} -> ${new}, gated on a real build."
    )

    if [[ "$dry_run" == true ]]; then
        argv+=(--dry-run)
    fi

    "${argv[@]}"
}

emit() {
    jq --null-input --compact-output \
        --arg attr "$1" --arg mode "$2" --arg old "$3" --arg new "$4" \
        --arg status "$5" --arg detail "$6" \
        '{ $attr, $mode, $old, $new, $status, $detail }' >>"$report"
}

# One package, start to finish.  Every path out of here goes through process(),
# which is what puts the file back in scan mode.
process_one() {
    local attr="$1"
    local mode version file branch new_version output changed touched

    mode="$(field_of "$attr" mode)"
    version="$(field_of "$attr" version)"
    branch="$(field_of "$attr" branch)"

    case "$mode" in
        stable | branch) ;;
        pinned | follows | report | external | manual)
            local detail
            detail="$(field_of "$attr" reason)"
            [[ -n "$detail" ]] || detail="mode ${mode}"
            emit "$attr" "$mode" "$version" "$version" skipped "$detail"
            return 0
            ;;
        *)
            emit "$attr" "$mode" "$version" "$version" error "unknown mode ${mode}"
            return 0
            ;;
    esac

    file="$(field_of "$attr" position)"
    file="${file%%:*}"
    if [[ -z "$file" ]]; then
        emit "$attr" "$mode" "$version" "$version" error 'no meta.position'
        return 0
    fi
    file="${file#"${repo_root}/"}"

    snapshot="$(mktemp)"
    snapshot_target="$file"
    cp "${repo_root}/${file}" "$snapshot"

    local -a argv=()
    mapfile -t argv < <(nix_update_argv "$attr" "$mode" "$branch")

    if ! output="$(cd "$repo_root" && "${argv[@]}" 2>&1)"; then
        emit "$attr" "$mode" "$version" "$version" failed \
            "$(tail -n 3 <<<"$output" | tr '\n' ' ')"
        return 0
    fi

    changed="$(git -C "$repo_root" diff --name-only -- "$file")"
    if [[ -z "$changed" ]]; then
        emit "$attr" "$mode" "$version" "$version" current ''
        return 0
    fi

    new_version="$(
        grep --extended-regexp --only-matching --max-count=1 \
            -- 'version = "[^"]*"' "${repo_root}/${file}" \
            | sed 's/version = "//; s/"$//'
    )" || new_version="$version"

    # The guard that makes "follow the branch it is already on" mean something.
    # --version=branch follows the repository's *default* branch, and if that
    # has been retargeted the new rev can be on a different line of development
    # entirely — which shows up as the date going backwards.
    local old_date new_date
    old_date="$(unstable_date "$version")"
    new_date="$(unstable_date "$new_version")"
    if [[ -n "$old_date" && -n "$new_date" && "$new_date" < "$old_date" ]]; then
        emit "$attr" "$mode" "$version" "$new_version" rejected \
            'the new commit is older than the pinned one; the default branch may have moved'
        return 0
    fi

    if [[ "$scan" == true ]]; then
        emit "$attr" "$mode" "$version" "$new_version" would-update ''
        return 0
    fi

    if ! handle_secondaries "$attr" "$file"; then
        emit "$attr" "$mode" "$version" "$new_version" failed \
            'a secondary source could not be brought along'
        return 0
    fi

    tidy "$file"

    # One file per commit is what ./forge-pr.sh can sign through the contents
    # API.  Anything wider is reported rather than delivered; nothing here
    # actually produces it, and finding out loudly beats a half-pushed bump.
    touched="$(git -C "$repo_root" diff --name-only | wc -l)"
    if [[ "$touched" -gt 1 && "$deliver" != none ]]; then
        keep_changes=true
        emit "$attr" "$mode" "$version" "$new_version" needs-review \
            "the rewrite touched ${touched} files, which the single-file commit path cannot deliver"
        return 0
    fi

    keep_changes=true

    case "$deliver" in
        commit) commit_locally "$attr" "$file" "$version" "$new_version" ;;
        pr) open_pull_request "$attr" "$file" "$version" "$new_version" ;;
        none) ;;
    esac

    emit "$attr" "$mode" "$version" "$new_version" updated ''
}

process() {
    snapshot=''
    snapshot_target=''
    keep_changes=false

    process_one "$1" || log "$1: the driver itself failed; the tree has been restored"

    if [[ -n "$snapshot" ]]; then
        if [[ "$keep_changes" != true ]]; then
            cp "$snapshot" "${repo_root}/${snapshot_target}"
        fi
        rm -f "$snapshot"
    fi
}

print_report() {
    printf '\n%-34s %-8s %-12s %-26s %s\n' ATTRIBUTE MODE STATUS VERSION DETAIL

    jq --raw-output '
        [ .attr, .mode, .status,
          (if .old == .new then .old else .old + " -> " + .new end),
          .detail ]
        | @tsv
    ' "$report" \
        | sort \
        | while IFS=$'\t' read -r attr mode status version detail; do
            printf '%-34s %-8s %-12s %-26s %s\n' "$attr" "$mode" "$status" "$version" "$detail"
        done

    printf '\n'
    jq --raw-output --slurp '
        group_by(.status) | map("\(length) \(.[0].status)") | join(", ")
    ' "$report"
}

main() {
    parse_args "$@"
    require_tools

    policy="$(resolve_policy)" \
        || die 'could not evaluate scripts/update-universe.nix; if a package was named, check the spelling of its attribute path'

    if [[ "$policy_only" == true ]]; then
        jq '.' <<<"$policy"
        return 0
    fi

    # Only a whole-universe run can answer this, and only a whole-universe run
    # is asking: a named subset skips the walk that would compute it.
    if [[ "$(jq --raw-output '.complete' <<<"$policy")" == true ]]; then
        local missing
        missing="$(jq --raw-output '.missing | join(", ")' <<<"$policy")"
        [[ -z "$missing" ]] \
            || die "these pkgs/ directories have no attribute path: ${missing}"
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        mapfile -t selected < <(jq --raw-output '.packages | keys[]' <<<"$policy")
    fi

    report="$(mktemp)"
    : >"$report"

    local attr moved
    for attr in "${selected[@]}"; do
        jq --exit-status --arg a "$attr" '.packages | has($a)' <<<"$policy" >/dev/null \
            || die "no such attribute: ${attr}"

        process "$attr"

        if [[ "$limit" -gt 0 ]]; then
            moved="$(jq --raw-output --slurp \
                '[ .[] | select(.status == "updated" or .status == "would-update") ] | length' \
                "$report")"
            if [[ "$moved" -ge "$limit" ]]; then
                log "reached --limit=${limit}"
                break
            fi
        fi
    done

    print_report

    if [[ -n "$json_out" ]]; then
        jq --slurp '.' "$report" >"$json_out"
        log "report written to ${json_out}"
    fi

    rm -f "$report"
}

main "$@"
