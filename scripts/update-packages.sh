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
# ## Why nix-update is pointed at ../default.nix rather than at the flake
#
# `nix-update --flake` costs two things per package, and neither buys anything
# here.  Its `get_flake_import_path()` runs `nix flake metadata --json` and, in
# its own words, "always re-copies the flake", twice per invocation; then
# `builtins.getFlake` evaluates flake.nix through flake-parts before it can
# reach one attribute.  `--file ../.` is `import ./default.nix`, which is lazy:
# 0.17s against the ~4.8s of CPU per package the flake path was spending.
#
# It also *fixes* four packages.  nix-update's eval.nix looks the attribute up
# in `flake.packages.${system}` and then in the flake's own root — never in
# `legacyPackages`.  So exactly the attributes that are not top-level
# derivations could not be resolved at all: `internalPackages.chemfiles`,
# `internalPackages.trexio`, `python313Packages.monty` and
# `python313Packages.tensorpotential` were reported as `failed` with a bare
# CalledProcessError.  ../default.nix has all four.
#
# The price is that `<nixpkgs>` is no longer pinned by flake.lock, so NIX_PATH
# has to be set from ./locked-nixpkgs.sh before nix-update runs — see the note
# in that script for what a green answer against the wrong nixpkgs is worth.
#
# ## Scan mode does not download anything
#
# nix-update rewrites a src hash by building the fetcher with `outputHash = ""`
# and reading the right answer out of the *failure* message.  A failed
# fixed-output derivation leaves nothing behind, so every package that moved was
# downloading its whole source and throwing it away — for a value scan mode then
# restored.  `--no-src` skips that step and keeps the version rewrite, which is
# the only part a scan reads back.
#
# ## Parallelism is a scan-mode feature
#
# Packages are independent and a scan touches one file each, so --jobs fans them
# out; the report becomes one file per attribute in a directory rather than a
# shared append.  It is refused for anything that writes, because --deliver
# drives git, --limit is a running count across the whole run, and neither
# survives being raced.  A file claimed by two attributes drops the run back to
# one worker rather than letting them overwrite each other's snapshots.
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
jobs=0
from_file=''
json_out=''
policy_only=false
policy=''
report_dir=''
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
  --jobs=N            packages to scan at once (scan mode only; 0 = one per core, capped at 8)
  --from=PATH         take the attributes from a previous --json report's would-update rows
  --no-build          skip the build gate; scan mode never builds anyway
  --dry-run           with --deliver=pr, print the API calls without issuing them
  --json=PATH         write the machine-readable report here
  --policy            print the resolved policy as JSON and exit
  -h, --help          this

With no ATTR and no --from, every package whose policy makes it actionable is
attempted.
EOF
}

# The would-update rows of a report this script wrote earlier, and nothing else.
# `rejected` is a guard's considered answer and `failed` is a bug to fix; either
# one fed back in would be asking the same question a second time and getting
# the same reply.  A row that has gone stale since the scan is harmless — the
# bump is recomputed from scratch, and a package that has since caught up simply
# reports `current`.
attrs_from_report() {
    local file="$1"

    [[ -r "$file" ]] || die "cannot read ${file}; run a scan with --json=${file} first"

    jq --raw-output '.[] | select(.status == "would-update") | .attr' "$file" \
        || die "${file} is not a report this script wrote"
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
            --jobs=*) jobs="${1#*=}" ;;
            --from=*) from_file="${1#*=}" ;;
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
    [[ "$jobs" =~ ^[0-9]+$ ]] || die '--jobs takes a number'

    # One worker per core for a scan, and one for everything else.  The cap is
    # about the far end rather than this one: a scan is a hundred-odd requests to
    # a handful of forges, and fanning that out further is rude before it is
    # faster.
    if [[ "$jobs" -eq 0 ]]; then
        if [[ "$scan" == true ]]; then
            jobs="$(nproc 2>/dev/null || echo 4)"
            [[ "$jobs" -le 8 ]] || jobs=8
        else
            jobs=1
        fi
    fi

    if [[ "$jobs" -gt 1 && "$scan" != true ]]; then
        die '--jobs>1 needs --scan; a run that writes drives git and counts --limit as it goes'
    fi

    [[ -z "$from_file" || ${#selected[@]} -eq 0 ]] \
        || die '--from and a named attribute are two ways to choose; pick one'
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
    for flag in --file --build --version --no-src --version-regex --use-github-releases; do
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
# Exported once, and for everything: since ../default.nix rather than the flake
# is what `nix-update` now imports, `<nixpkgs>` is what resolves its `pkgs`
# default, and an unset NIX_PATH means the registry decides which nixpkgs a bump
# was evaluated and built against.  ./locked-nixpkgs.sh exists to say why that
# answer is worthless.
pin_nixpkgs() {
    NIX_PATH="$("${repo_root}/scripts/locked-nixpkgs.sh")"
    export NIX_PATH
}

resolve_policy() {
    local only='[ ]'

    if [[ ${#selected[@]} -gt 0 ]]; then
        only="[ $(printf '"%s" ' "${selected[@]}")]"
    fi

    # `--expr 'import … { }'` rather than `--file`: nix-instantiate hands a
    # file's value back as-is, and this one is a function, so it has to be
    # applied here for its `pkgs ? import <nixpkgs> { }` default to fire.
    nix-instantiate \
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

# The part of a version that claims to be a version: the `-unstable-<date>`
# marker dropped, and then a trailing PEP 440 pre-release or dev segment, so
# that `0.12.dev20260807` and `0.12` compare equal rather than backwards.  Two
# of those are the same release as far as this guard is concerned, and `sort
# --version-sort` has never heard of PEP 440.  `.cp` and friends survive, since
# the marker has to be followed by digits or by the end of the string.
version_prefix() {
    sed --regexp-extended \
        -e 's/-unstable-[0-9]{4}-[0-9]{2}-[0-9]{2}$//' \
        -e 's/[.-]?(alpha|beta|post|pre|dev|rc|a|b)[0-9]*$//' \
        <<<"$1"
}

# Prints a reason and succeeds when the bump makes the version *worse*.
#
# The date guard below catches a rev that went backwards.  This catches the
# other half, and it is the more common one here: a dozen packages in this
# repository carry a hand-written version because upstream's newest tag is years
# behind its default branch — ../pkgs/vise is 827 commits past v0.1.13, and
# ../pkgs/pydefect 764 past v0.2.6 — so `nix-update` reads the tag, writes it
# over the real version, and reports a downgrade as an update.  Rejecting is the
# conservative answer: a package that needs the bump gets a `versionRegex` in
# its passthru.updatePolicy, which is a decision for a human.
#
# The first rule is about shape rather than order.  `mdanalysis` was offered
# `release-2.10.0` and `fairchem-data-oc` `fairchem_core-2.22.0`, both of which
# are a ref name that reached the version field, and neither of which sorts
# anywhere meaningful.
version_regression() {
    local old new first
    old="$(version_prefix "$1")"
    new="$(version_prefix "$2")"

    [[ -n "$old" && -n "$new" && "$old" != "$new" ]] || return 1
    [[ "$old" =~ ^[0-9] ]] || return 1

    if [[ ! "$new" =~ ^[0-9] ]]; then
        printf 'the new version does not begin with a digit; a branch or tag name has leaked into it'
        return 0
    fi

    first="$(printf '%s\n%s\n' "$old" "$new" | sort --version-sort | head --lines=1)"
    if [[ "$first" == "$new" ]]; then
        printf "the new version sorts before the pinned one; upstream's newest tag is behind the version set here"
        return 0
    fi

    return 1
}

nix_update_argv() {
    local attr="$1" mode="$2" branch="$3" version_regex="$4"
    # --file rather than --flake; see the header for what that costs and fixes.
    local -a argv=(nix-update --file "$repo_root")

    # `--use-github-releases` comes along with the regex rather than being a
    # second thing to declare, because the two failures are the same failure.
    # A regex is declared when a repository carries several tag series; the
    # default fetcher reads `releases.atom`, which returns only the newest
    # handful of releases; so a series that has not released lately is not in
    # the feed *at all* and the regex matches nothing.  That is what happened to
    # `fairchem-data-omat`, whose tag is from 2025-11-14, while `fairchem-core`
    # and `fairchem-data-omol` passed only because they happened to be inside
    # the window that week.  Relying on that is an intermittent failure waiting
    # for a quiet month.  `--use-github-releases` walks the paginated API
    # instead, and honours GITHUB_TOKEN; unauthenticated it is 60 requests an
    # hour against the four packages that declare a regex today.
    if [[ -n "$version_regex" ]]; then
        argv+=("--version-regex=${version_regex}" --use-github-releases)
    fi

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

    # A scan reads the rewritten `version` line back and then restores the file,
    # so the hash is work with no reader.  Skipping it is the difference between
    # a scan that downloads every moving package's source and one that asks each
    # forge what its latest tag is.
    if [[ "$scan" == true ]]; then
        argv+=(--no-src)
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

    # `-f` rather than `.#`, to match the driver: `internalPackages.trexio` is
    # the one attribute here that declares a secondary source *and* is not a
    # flake output, so a flake reference could never have realised it.
    source_path="$(
        cd "$repo_root" && nix build --no-link --print-out-paths \
            --file "$repo_root" "${attr}.src" 2>/dev/null
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

# One file per attribute rather than one shared append, so that workers running
# at once cannot interleave a line.  Attribute paths are the only thing here
# with a dot in them and nothing has a slash, so the name is the filename.
emit() {
    jq --null-input --compact-output \
        --arg attr "$1" --arg mode "$2" --arg old "$3" --arg new "$4" \
        --arg status "$5" --arg detail "$6" \
        '{ $attr, $mode, $old, $new, $status, $detail }' >"${report_dir}/${1}.json"
}

# Every line emitted so far, in no particular order.  Each reader sorts or
# slurps for itself.
report_json() {
    cat "$report_dir"/*.json 2>/dev/null || true
}

# One package, start to finish.  Every path out of here goes through process(),
# which is what puts the file back in scan mode.
process_one() {
    local attr="$1"
    local mode version file branch version_regex new_version output touched regression

    mode="$(field_of "$attr" mode)"
    version="$(field_of "$attr" version)"
    branch="$(field_of "$attr" branch)"
    version_regex="$(field_of "$attr" versionRegex)"

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
    mapfile -t argv < <(nix_update_argv "$attr" "$mode" "$branch" "$version_regex")

    if ! output="$(cd "$repo_root" && "${argv[@]}" 2>&1)"; then
        emit "$attr" "$mode" "$version" "$version" failed \
            "$(tail -n 3 <<<"$output" | tr '\n' ' ')"
        return 0
    fi

    # Against the snapshot rather than against git.  Two reasons: `git diff`
    # refreshes the index and so takes .git/index.lock, which a dozen workers
    # will collide on; and a file that was already dirty before the run would
    # have reported every one of its packages as moving.
    if cmp --silent "$snapshot" "${repo_root}/${file}"; then
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

    # And the same question asked of the version rather than the date.  Note
    # that this fires even when the date moved forward: a newer commit whose
    # nearest tag is older still leaves the file claiming a version this
    # repository has already passed.
    if regression="$(version_regression "$version" "$new_version")"; then
        emit "$attr" "$mode" "$version" "$new_version" rejected "$regression"
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

# Any file two actionable attributes both point `meta.position` at.  Nothing
# does today — `chemfiles` is ../pkgs/chemfiles and `internalPackages.chemfiles`
# is ../pkgs/chemfiles-python, which is the closest it comes — but a package
# added as a second attribute on one file would have two workers snapshotting
# and restoring it at once, and the loser's bump would vanish silently.
shared_positions() {
    jq --raw-output '
        [ .packages[]
          | select(.mode == "stable" or .mode == "branch")
          | (.position // "" | split(":")[0])
          | select(. != "") ]
        | group_by(.)
        | map(select(length > 1) | .[0])
        | join(", ")
    ' <<<"$policy"
}

run_serial() {
    local attr moved

    for attr in "$@"; do
        process "$attr"

        if [[ "$limit" -gt 0 ]]; then
            moved="$(report_json | jq --raw-output --slurp \
                '[ .[] | select(.status == "updated" or .status == "would-update") ] | length')"
            if [[ "$moved" -ge "$limit" ]]; then
                log "reached --limit=${limit}"
                break
            fi
        fi
    done
}

# `wait -n` as the slot, rather than batching: a batch runs at the speed of its
# slowest member, and the spread here is wide — a package that is already
# current answers in a second, one that has to ask a forge for a tag list takes
# ten.  No --limit to honour, since --jobs>1 refuses to coexist with it.
#
# `|| true` on both waits because the workers report their own failures into the
# report directory; a non-zero status reaching `set -e` here would abandon the
# jobs still running, and with them the snapshots they have yet to restore.
run_parallel() {
    local attr running=0

    log "scanning ${#} packages, ${jobs} at a time"

    for attr in "$@"; do
        process "$attr" &
        running=$((running + 1))
        if [[ "$running" -ge "$jobs" ]]; then
            wait -n || true
            running=$((running - 1))
        fi
    done

    wait || true
}

print_report() {
    printf '\n%-34s %-8s %-12s %-26s %s\n' ATTRIBUTE MODE STATUS VERSION DETAIL

    report_json \
        | jq --raw-output '
        [ .attr, .mode, .status,
          (if .old == .new then .old else .old + " -> " + .new end),
          .detail ]
        | @tsv
    ' \
        | sort \
        | while IFS=$'\t' read -r attr mode status version detail; do
            printf '%-34s %-8s %-12s %-26s %s\n' "$attr" "$mode" "$status" "$version" "$detail"
        done

    printf '\n'
    report_json \
        | jq --raw-output --slurp '
        group_by(.status) | map("\(length) \(.[0].status)") | join(", ")
    '
}

main() {
    parse_args "$@"
    require_tools

    # Before the policy is resolved, not after: `selected` is what becomes the
    # `only` argument, and that is the difference between evaluating thirty-five
    # attributes and evaluating the whole overlaid package set.
    if [[ -n "$from_file" ]]; then
        mapfile -t selected < <(attrs_from_report "$from_file")

        if [[ ${#selected[@]} -eq 0 ]]; then
            log "${from_file} lists nothing as would-update"
            return 0
        fi

        log "taking ${#selected[@]} attribute(s) from ${from_file}"
    fi

    pin_nixpkgs

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

    local attr
    for attr in "${selected[@]}"; do
        jq --exit-status --arg a "$attr" '.packages | has($a)' <<<"$policy" >/dev/null \
            || die "no such attribute: ${attr}"
    done

    if [[ "$jobs" -gt 1 ]]; then
        local shared
        shared="$(shared_positions)"
        if [[ -n "$shared" ]]; then
            log "two attributes claim ${shared}; running one at a time so their snapshots cannot race"
            jobs=1
        fi
    fi

    report_dir="$(mktemp --directory)"

    if [[ "$jobs" -gt 1 ]]; then
        run_parallel "${selected[@]}"
    else
        run_serial "${selected[@]}"
    fi

    print_report

    if [[ -n "$json_out" ]]; then
        report_json | jq --slurp '.' >"$json_out"
        log "report written to ${json_out}"
    fi

    rm --recursive --force "$report_dir"
}

main "$@"
