#!/usr/bin/env bash
#
# Print a usable PATH for the Claude Code bubblewrap sandbox.
#
#   export PATH="$(scripts/sandbox-path.sh)"
#
# The sandbox inherits the host's PATH verbatim, but mounts almost none of it.
# NIX_PROFILES names six profile directories -- /run/current-system/sw,
# /etc/profiles/per-user/$USER, ~/.nix-profile and the rest -- and inside the
# sandbox every one of them is absent, because only /nix/store, the project
# directory and a handful of dotfiles are bind-mounted.  What survives is /bin,
# and /bin holds exactly two entries: bash and sh.
#
# So a session can start with `ls`, `git`, `sed` and `nix` all off PATH while
# the programs themselves sit in the store, readable, a few directories away.
# Rediscovering them by hand costs several `for d in /nix/store/*/bin` sweeps
# per session, and the answers are not reusable: store paths change whenever the
# sandbox is rebuilt.
#
# The anchor is /bin/bash.  It is a symlink into a profile the sandbox wrapper
# builds for itself, `claude-sandbox-path`, which carries the ~600 programs the
# sandbox is *meant* to expose -- coreutils, git, rg, jq, just, nix, shellcheck,
# shfmt, python3.  Resolving that symlink names the live generation exactly, and
# is why this does not glob for the profile and guess: five generations of it are
# in the store here, and only one is the one this sandbox was built from.
#
# Bootstrapping is the awkward part, since resolving a symlink needs `readlink`
# and `readlink` is one of the missing programs.  Hence two steps: borrow a
# `readlink` from whichever candidate profile has one, then use it to find the
# real answer.  Any generation's readlink resolves a symlink identically, so it
# does not matter which one lends it.
#
# What this does NOT provide is the devShell.  nixfmt, statix and deadnix are
# not in the sandbox profile and never will be; they come from `nix develop`.
# Getting `nix` onto PATH is the point -- it is what makes that reachable again.

set -euo pipefail

shopt -s nullglob

fail() {
    printf 'sandbox-path.sh: %s\n' "$1" >&2
    exit 1
}

candidates=(/nix/store/*-claude-sandbox-path/bin)
[[ ${#candidates[@]} -gt 0 ]] \
    || fail 'no claude-sandbox-path profile in /nix/store; is this a sandbox?'

# Step one: any candidate's readlink will do.
readlink_bin=''
for dir in "${candidates[@]}"; do
    if [[ -x "$dir/readlink" ]]; then
        readlink_bin="$dir/readlink"
        break
    fi
done
[[ -n "$readlink_bin" ]] \
    || fail 'no readlink in any claude-sandbox-path profile'

# Step two: /bin/bash names the generation this sandbox actually runs.
#
# One hop, deliberately.  /bin/bash points at the profile's bin/bash, and that
# is itself a symlink on to the bash package, so --canonicalize walks straight
# past the answer and lands in bash-5.3/bin -- which has no `env`, so the
# fallback below silently fires and picks an arbitrary generation.  Reading the
# link once stops exactly where the profile is.
profile_bin=''
if [[ -L /bin/bash ]]; then
    resolved="$("$readlink_bin" /bin/bash)"
    profile_bin="${resolved%/bash}"
fi

# Fall back to the borrowed candidate if /bin/bash is not the expected symlink,
# so a wrapper that changes shape degrades to "probably right" instead of dying.
[[ -x "$profile_bin/env" ]] || profile_bin="${readlink_bin%/readlink}"

# Keep the inherited PATH behind it rather than replacing it: most of its
# entries are dead inside the sandbox, but the few live ones -- a devShell
# already entered, ~/.local/bin -- must not be dropped.
if [[ -n "${PATH:-}" ]]; then
    printf '%s:%s\n' "$profile_bin" "$PATH"
else
    printf '%s\n' "$profile_bin"
fi
