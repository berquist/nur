#!/usr/bin/env bash
#
# forge-pr.sh — put one changed file on a branch and open a pull request for it,
# through the forge's own API, on GitHub or on Forgejo.
#
#   scripts/forge-pr.sh --branch=update/qcportal --file=pkgs/qcportal/default.nix \
#       --message='chore(deps): update qcportal to 0.70' \
#       --title='chore(deps): update qcportal to 0.70' \
#       --body='Automated version bump.'
#
#   scripts/forge-pr.sh --dry-run …      print the calls, issue none, need no token
#
# ## Why the API and not git
#
# Commits in this repository are signed, and an unattended runner cannot hold
# the key that signs them.  Creating the commit through the *contents* API moves
# the signature to the forge: GitHub signs web-flow commits, and Forgejo signs
# API commits wherever `[repository.signing] CRUD_ACTIONS` is configured on the
# instance.  So the runner needs a token and nothing else — no key, no git
# identity, no push credentials — and the resulting commit shows as verified.
#
# **Check that it does, on the first live run.**  Both halves of that claim are
# instance- and token-dependent, and a commit that comes back unverified is a
# silent failure of the whole arrangement.  The other thing to check once: a
# pull request opened with GitHub's automatic GITHUB_TOKEN does **not** trigger
# `pull_request` workflows, so ../.github/workflows/build.yml would never run on
# an updater PR.  If that bites, the job needs a fine-grained PAT instead.
#
# ## One file
#
# GitHub's contents API commits one file at a time, and that is the whole of
# this script's reach.  It is enough: a `nix-update` rewrite touches one
# derivation file and `nix flake update` touches one lock file.  Anything wider
# is caught by the caller — see ./update-packages.sh — and reported rather than
# half-delivered.  Forgejo has a multi-file endpoint and GitHub has the GraphQL
# `createCommitOnBranch` mutation if that ever has to change.
#
# ## Branch naming
#
# `update/<attr>`, with no version in it, so a re-run updates the pull request
# that is already open rather than leaving a trail of stale ones.  An existing
# branch is deleted and recreated, so the pull request carries exactly one
# signed commit rather than a pile of amendments.  docs/version-updates.md §10
# listed this as an open question; this is the answer.
#
# ## Configuration
#
#   FORGE        github (default) | forgejo
#   FORGE_TOKEN  the API token; required unless --dry-run
#   FORGE_REPO   owner/repo; defaults to what `git remote get-url origin` says
#   FORGE_HOST   Forgejo base URL, e.g. https://codeberg.org; ignored on GitHub
#   FORGE_BASE   the branch to open against; defaults to main
#
# Keep the token in ../.envrc.local, which is gitignored and is already this
# repository's convention for credentials.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

forge="${FORGE:-github}"
token="${FORGE_TOKEN:-}"
host="${FORGE_HOST:-}"
base="${FORGE_BASE:-main}"
repo="${FORGE_REPO:-}"

branch=''
file=''
message=''
title=''
body=''
dry_run=false

usage() {
    cat >&2 <<'EOF'
usage: forge-pr.sh --branch=NAME --file=PATH --message=TEXT --title=TEXT --body=TEXT [--dry-run]

  --branch    the head branch; created from FORGE_BASE, recreated if it exists
  --file      repository-relative path of the single file to commit
  --message   commit message
  --title     pull request title
  --body      pull request body
  --dry-run   print the calls that would be made; issues none and needs no token
EOF
}

die() {
    printf 'forge-pr: %s\n' "$1" >&2
    exit 1
}

log() {
    printf 'forge-pr: %s\n' "$1" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch=*) branch="${1#*=}" ;;
            --file=*) file="${1#*=}" ;;
            --message=*) message="${1#*=}" ;;
            --title=*) title="${1#*=}" ;;
            --body=*) body="${1#*=}" ;;
            --dry-run) dry_run=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "unknown option $1" ;;
        esac
        shift
    done

    [[ -n "$branch" ]] || die '--branch is required'
    [[ -n "$file" ]] || die '--file is required'
    [[ -n "$message" ]] || die '--message is required'
    [[ -n "$title" ]] || die '--title is required'
    [[ -r "${repo_root}/${file}" ]] || die "${file} is not readable"

    case "$forge" in
        github | forgejo) ;;
        *) die "FORGE must be github or forgejo, not ${forge}" ;;
    esac

    if [[ "$forge" == forgejo && -z "$host" && "$dry_run" != true ]]; then
        die 'FORGE_HOST is required for Forgejo'
    fi

    [[ -n "$token" || "$dry_run" == true ]] || die 'FORGE_TOKEN is not set'
}

# owner/repo out of the origin remote, so neither the workflow nor a local run
# has to repeat it.  Handles both the ssh and https spellings, with or without
# the .git suffix.
detect_repo() {
    [[ -z "$repo" ]] || return 0

    local url
    url="$(git -C "$repo_root" remote get-url origin 2>/dev/null)" \
        || die 'no origin remote, and FORGE_REPO is not set'

    url="${url%.git}"
    url="${url#*://}"
    url="${url#*@}"
    repo="${url#*[:/]}"

    # Whatever is left should be exactly owner/repo.
    [[ "$repo" == */* && "$repo" != */*/* ]] \
        || die "could not read owner/repo out of ${url}; set FORGE_REPO"
}

api_root() {
    case "$forge" in
        github) printf 'https://api.github.com/repos/%s' "$repo" ;;
        forgejo) printf '%s/api/v1/repos/%s' "${host%/}" "$repo" ;;
    esac
}

auth_header() {
    case "$forge" in
        github) printf 'Authorization: Bearer %s' "$token" ;;
        forgejo) printf 'Authorization: token %s' "$token" ;;
    esac
}

accept_header() {
    case "$forge" in
        github) printf 'Accept: application/vnd.github+json' ;;
        forgejo) printf 'Accept: application/json' ;;
    esac
}

# One request.  Prints the response body on stdout and the status code on fd 3,
# so a caller can tell 422 "already exists" from a real failure without parsing
# the body.
declare -g last_status=0
api() {
    local method="$1" url="$2" payload="${3:-}"
    local -a argv=(
        curl --silent --show-error
        --request "$method"
        --header "$(auth_header)"
        --header "$(accept_header)"
        --write-out '\n%{http_code}'
    )

    if [[ -n "$payload" ]]; then
        argv+=(--header 'Content-Type: application/json' --data "$payload")
    fi

    local response
    response="$("${argv[@]}" "$url")"
    last_status="${response##*$'\n'}"
    printf '%s' "${response%$'\n'*}"
}

show() {
    local method="$1" url="$2" payload="${3:-}"
    printf '  %-6s %s\n' "$method" "$url"
    if [[ -n "$payload" ]]; then
        jq --indent 4 '.' <<<"$payload" | sed 's/^/      /'
    fi
}

# ---------------------------------------------------------------------------
# The four calls.  Everything forge-specific is in these; the flow below is
# shared.
# ---------------------------------------------------------------------------

base_sha_call() {
    case "$forge" in
        github) printf '%s/git/ref/heads/%s' "$(api_root)" "$base" ;;
        forgejo) printf '%s/branches/%s' "$(api_root)" "$base" ;;
    esac
}

base_sha_from() {
    case "$forge" in
        github) jq --raw-output '.object.sha' <<<"$1" ;;
        forgejo) jq --raw-output '.commit.id' <<<"$1" ;;
    esac
}

create_branch_payload() {
    local sha="$1"
    case "$forge" in
        github)
            jq --null-input --compact-output \
                --arg ref "refs/heads/${branch}" --arg sha "$sha" \
                '{ $ref, $sha }'
            ;;
        forgejo)
            jq --null-input --compact-output \
                --arg new_branch_name "$branch" --arg old_branch_name "$base" \
                '{ $new_branch_name, $old_branch_name }'
            ;;
    esac
}

create_branch_url() {
    case "$forge" in
        github) printf '%s/git/refs' "$(api_root)" ;;
        forgejo) printf '%s/branches' "$(api_root)" ;;
    esac
}

delete_branch_url() {
    case "$forge" in
        github) printf '%s/git/refs/heads/%s' "$(api_root)" "$branch" ;;
        forgejo) printf '%s/branches/%s' "$(api_root)" "$branch" ;;
    esac
}

contents_url() {
    printf '%s/contents/%s' "$(api_root)" "$file"
}

commit_payload() {
    local blob_sha="$1" content="$2"
    jq --null-input --compact-output \
        --arg message "$message" --arg content "$content" \
        --arg branch "$branch" --arg sha "$blob_sha" \
        '{ $message, $content, $branch, $sha }'
}

pull_payload() {
    jq --null-input --compact-output \
        --arg head "$branch" --arg base "$base" \
        --arg title "$title" --arg body "$body" \
        '{ $head, $base, $title, $body }'
}

# ---------------------------------------------------------------------------

encoded_content() {
    base64 --wrap=0 <"${repo_root}/${file}"
}

dry_run_report() {
    printf 'forge-pr: %s, %s, %s -> %s\n\n' "$forge" "$repo" "$file" "$branch"
    show GET "$(base_sha_call)"
    show DELETE "$(delete_branch_url)" ''
    show POST "$(create_branch_url)" "$(create_branch_payload '<sha from the GET above>')"
    show GET "$(contents_url)?ref=${base}"
    show PUT "$(contents_url)" \
        "$(commit_payload '<blob sha from the GET above>' "<base64 of ${file}, $(wc -c <"${repo_root}/${file}") bytes>")"
    show POST "$(api_root)/pulls" "$(pull_payload)"
    printf '\nforge-pr: dry run, nothing was issued\n'
}

main() {
    parse_args "$@"
    command -v jq >/dev/null || die 'jq is not on PATH'
    command -v curl >/dev/null || die 'curl is not on PATH'
    detect_repo

    if [[ "$dry_run" == true ]]; then
        dry_run_report
        return 0
    fi

    local response base_sha blob_sha content

    response="$(api GET "$(base_sha_call)")"
    [[ "$last_status" == 200 ]] || die "could not read ${base}: HTTP ${last_status} ${response}"
    base_sha="$(base_sha_from "$response")"

    # Delete first, unconditionally, so a re-run replaces the open pull
    # request's single commit rather than stacking another one on it.  A 404
    # here is the ordinary case — the branch does not exist yet.
    api DELETE "$(delete_branch_url)" >/dev/null
    case "$last_status" in
        200 | 204) log "recreating existing branch ${branch}" ;;
        404 | 422) ;;
        *) die "could not delete ${branch}: HTTP ${last_status}" ;;
    esac

    response="$(api POST "$(create_branch_url)" "$(create_branch_payload "$base_sha")")"
    [[ "$last_status" =~ ^20[01]$ ]] \
        || die "could not create ${branch}: HTTP ${last_status} ${response}"

    # The blob sha the contents API needs is the file's on the *base*, which is
    # what the new branch points at.
    response="$(api GET "$(contents_url)?ref=${base}")"
    [[ "$last_status" == 200 ]] \
        || die "could not read ${file} on ${base}: HTTP ${last_status} ${response}"
    blob_sha="$(jq --raw-output '.sha' <<<"$response")"

    content="$(encoded_content)"
    response="$(api PUT "$(contents_url)" "$(commit_payload "$blob_sha" "$content")")"
    [[ "$last_status" =~ ^20[013]$ ]] \
        || die "could not commit ${file}: HTTP ${last_status} ${response}"

    local verified commit_sha
    commit_sha="$(jq --raw-output '.commit.sha // ""' <<<"$response")"
    verified="$(jq --raw-output '.commit.verification.verified // "unknown"' <<<"$response")"
    log "committed ${commit_sha} on ${branch}, verified=${verified}"
    if [[ "$verified" != true ]]; then
        log 'the forge did not sign that commit -- see the note at the top of this script'
    fi

    response="$(api POST "$(api_root)/pulls" "$(pull_payload)")"
    case "$last_status" in
        200 | 201)
            log "opened $(jq --raw-output '.html_url // .url' <<<"$response")"
            ;;
        409 | 422)
            log "a pull request for ${branch} is already open; its branch now carries the new commit"
            ;;
        *)
            die "could not open a pull request: HTTP ${last_status} ${response}"
            ;;
    esac
}

main "$@"
