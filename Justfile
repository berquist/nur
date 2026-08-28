# Justfile
#
# The commands CI runs, runnable locally.
#
# .github/workflows/build.yml calls the ci-* recipes below rather than
# spelling the commands out itself, so there is exactly one copy of each and
# `just ci` locally is the same thing the runner does.
#
# Everything here needs a working nix-daemon.  For the eval-only subset that
# runs without one, see scripts/no-daemon-check.sh (`just check-no-daemon`).
#
# These recipes work under both CppNix and Lix.  Nothing here parses the output
# of `nix --version`, which is the one thing that reliably breaks across the
# two — see the note on ci-build.

nixpkgs_url := "https://github.com/NixOS/nixpkgs/archive/refs/heads"
default_channel := "nixpkgs-unstable"

# The nixPath matrix in .github/workflows/build.yml, in the same order.
channels := "nixpkgs-unstable nixos-unstable nixos-26.05"

# The binary cache, without the ".cachix.org" suffix.  Same value as the
# cachixName matrix entry in .github/workflows/build.yml.
cachix_name := "nur-berquist"

# GitHub Actions sets NIX_PATH itself, via install-nix-action and the workflow
# matrix.  Honour it when present so the ci-* recipes are channel-agnostic, and
# fall back to the default channel for local runs.
export NIX_PATH := env_var_or_default("NIX_PATH", "nixpkgs=" + nixpkgs_url + "/" + default_channel + ".tar.gz")

[private]
default:
    @just --list

# ---------------------------------------------------------------------------
# CI steps.  These evaluate against the ambient NIX_PATH; use `just ci CHANNEL`
# to pin one.  Each mirrors a step in .github/workflows/build.yml.
# ---------------------------------------------------------------------------

# Report which nixpkgs <nixpkgs> resolves to.
ci-version:
    nix-instantiate --eval -E '(import <nixpkgs> {}).lib.version'

# Evaluate every package's metadata under restricted eval.
ci-eval:
    nix-env -f . -qa '*' --meta --xml \
      --allowed-uris https://static.rust-lang.org \
      --option restrict-eval true \
      --option allow-import-from-derivation true \
      --drv-path --show-trace \
      -I nixpkgs=$(nix-instantiate --find-file nixpkgs) \
      -I $PWD

# Deliberately NOT nix-build-uncached, which the NUR template used here.  That
# tool shells out to `nix --version` and parses the result with the literal
# format `nix (Nix) %d.%d.%d`; Lix answers `nix (Lix, like Nix) 2.x.y`, which
# cannot match, so it aborts with "Failed to get nix version" before doing any
# work.  That is a property of the tool, not of the environment — switching CI
# to Lix would break it there too.
#
# Its whole point is skipping paths already in *your* cache, and that cache is
# live now, but the saving is small: with the substituter configured, `nix
# build` fetches a cached path instead of building it anyway.  What is left is
# the evaluation and the round trip.  Worth revisiting only if that starts to
# hurt, and by then upstream may parse Lix's version string.
#
# `nix build` rather than `nix-build` because only the new CLI accepts -L, and
# it handles ci.nix's list-valued attribute fine.

# Build everything ci.nix reports as buildable and cacheable.
ci-build:
    nix build -L --no-link --keep-going -f ci.nix cacheOutputs

# Full CI sequence against one channel, e.g. `just ci nixos-26.05`.
ci channel=default_channel:
    @NIX_PATH=nixpkgs={{ nixpkgs_url }}/{{ channel }}.tar.gz just ci-version ci-eval ci-build

# Every channel in the workflow matrix. Stops at the first failure.
ci-matrix:
    #!/usr/bin/env bash
    set -euo pipefail
    for channel in {{ channels }}; do
      printf '\n==> %s\n' "$channel"
      just ci "$channel"
    done

# watch-exec rather than a nix.conf post-build-hook, which is the other way to
# get every build uploaded.  The hook is permanent, needs cachix on the
# *nix-daemon's* PATH, and needs the auth token readable by root; this is
# scoped to one command and needs neither.
#
# Be clear about what that scope is: watch-exec runs watch-store for the
# duration of the command, so it watches the whole store, not this command's
# derivation lineage.  A concurrent build in another shell is uploaded too.
# The bound is time, not provenance.  Paths the cache or an upstream
# substituter already holds are skipped, so a re-run after a no-op build
# uploads nothing.
#
# Wrapping `ci` rather than `ci-build` mirrors one workflow matrix leg
# exactly, and pins the channel the same way, so a push is never at the mercy
# of the ambient NIX_PATH.  The two eval steps it adds cost seconds.
#
# Needs `cachix` on PATH and a write token installed by `cachix authtoken`.
# No signing key: this cache signs server-side.  CI does the equivalent
# through cachix/cachix-action, which starts a store-watching daemon before
# the ci-eval and ci-build steps.

# One channel's CI sequence, pushed, e.g. `just push nixos-26.05`.
push channel=default_channel:
    cachix watch-exec {{ cachix_name }} -- just ci {{ channel }}

# One watch-store session covers all three channels, so a path built for two
# of them is uploaded once.

# Every channel in the workflow matrix, pushed.
push-matrix:
    cachix watch-exec {{ cachix_name }} -- just ci-matrix

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# -L keeps the full builder output rather than the last few lines, so the whole
# run can be redirected to a file.  Classic nix-build does not accept -L (it
# errors with "unrecognised flag"), but it streams build output by default, so
# the nix-build recipes below need nothing extra.

# Everything: all three eval suites, the dotdrop and harmonwig integration
# tests, every VM test, and the hooks.
check:
    nix flake check -L

# Every non-VM test reachable without the flake: the three eval suites and the
# dotdrop integration tests.  Not harmonwig — its cclib comes from a flake
# input, so `just harmonwig-tests` goes through the flake instead.
tests:
    nix-build tests -A all --no-out-link

# QCFractal module evaluation tests only — fast, no VM, stubbed packages.
qcfractal-eval-tests:
    nix-build tests -A qcarchive.all --no-out-link

# AiiDA module evaluation tests only — fast, no VM, stubbed packages.
aiida-eval-tests:
    nix-build tests -A aiida.all --no-out-link

# Cheminformatics overlay evaluation tests only — fast, no VM, nothing real
# built. This is where the cclib split is asserted.
cheminformatics-eval-tests:
    nix-build tests -A cheminformatics.all --no-out-link

# dotdrop integration tests. No VM, but these build the real package.
dotdrop-tests:
    nix-build tests -A dotdrop.all --no-out-link

# harmonwig integration tests. Through the flake: harmonwig's cclib is a flake
# input, so `nix-build tests` cannot produce a working one.
harmonwig-tests:
    nix build -L --no-link .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).harmonwig

# One VM integration test, e.g. `just vm-test server-local-db`. Needs KVM.
vm-test name:
    nix build -L --no-link .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).vm-{{ name }}

# Drop into the interactive driver for one VM test, e.g.
# `just vm-test-interactive daemon-local-db aiida`.
vm-test-interactive name suite="qcarchive":
    $(nix-build tests/{{ suite }}/vm.nix -A {{ name }}.driver)/bin/nixos-test-driver

# Adversarial ordering checks for aiida-core's suite — one polluter then its
# victims, serially, so a cross-test pollution bug is a build failure rather
# than a one-in-128 draw.  See the header of tests/aiida/ordering.nix.
#
# Every entry must be green here and red under `just aiida-ordering-control`.
# Not part of `just check`: each entry builds a full aiida-core variant.

# Adversarial ordering checks, e.g. `just aiida-ordering group-agroup`.
aiida-ordering name="all":
    nix-build tests/aiida/ordering.nix -A {{ name }} --no-out-link

# The negative control: same checks with each victim's guard undone again, so
# every one of them is expected to FAIL.  A check that stays green under this
# never reproduced the bug it claims to.  --keep-going because the whole point
# is to see all seven fail, not to stop at the first.

# Ordering checks with the guards removed — every one must fail.
aiida-ordering-control name="all":
    nix-build tests/aiida/ordering.nix --arg unguard true -A {{ name }} --keep-going --no-out-link

# The mirror of the ordering checks: each test module in a session of its own,
# so a test that quietly needs a neighbour to have run first fails outright
# rather than one run in 128.  One derivation, ~200 pytest sessions, so budget
# an hour or two — `just aiida-isolation tests/tools` to narrow it.

# Every aiida-core test module run alone, e.g. `just aiida-isolation tests/orm`.
aiida-isolation only="tests":
    nix-build tests/aiida/isolation.nix --argstr only {{ only }} --no-out-link

# Seconds, not minutes — it patches the source and reads it, without building
# aiida-core.  Run it after any aiida-core bump: new tests bring new hazards.

# Static scan for cross-test pollution hazards in aiida-core's suite.
aiida-pollution-scan:
    cat $(nix-build tests/aiida/pollution-scan.nix --no-out-link)

# Eval tests, VM test instantiation and a parse of every Nix file — the whole
# of what can be checked without a nix-daemon, and so the whole of what runs
# inside the Claude Code sandbox.

# Every check that works without a nix-daemon.
check-no-daemon:
    ./scripts/no-daemon-check.sh

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

# Build one package the NUR way, e.g. `just build qcfractal`.
build pkg:
    nix-build -A {{ pkg }} --no-out-link

# The flake counterpart, and not a stylistic alternative to `build` above: the
# five cclib dependants are `meta.broken` on the NUR path and flake.nix's
# `packages` replaces them with the cclibPkgs ones, so `just build harmonwig`
# stops at "Package is marked as broken" and only this recipe can build them.
# See the cclib split in AGENTS.md.
#
# -L for the same reason ci-build uses it: the whole builder output, so the run
# can be redirected to a file and read back with `just demux-log`.

# Build one package through the flake, e.g. `just build-flake harmonwig`.
build-flake pkg:
    nix build -L --no-link .#{{ pkg }}

# `--keep-going` interleaves every concurrent build line by line, so a redirected
# ci-build log is a dozen derivations shuffled together and no single failure
# reads straight through.  This undoes that:
#
#   just ci-build 2>&1 | tee log_ci
#   just demux-log -l log_ci        # which derivations spoke, and how much
#   just demux-log -o postopus log_ci
#
# `-o '(nix)'` gets nix's own lines — the build plan and the failure summary.

# Regroup a redirected `nix build -L` log so each derivation reads as one block.
demux-log +args:
    ./scripts/demux-build-log.sh {{ args }}

# Builds qcportal against a channel's *default* interpreter rather than the
# python313 the repo pins.
#
# With the pin and the meta.broken marking in place this now stops at "Package
# is marked as broken". Set NIXPKGS_ALLOW_BROKEN=1 to push past that and see
# the original "TypeError: type 'Array' is not subscriptable" out of
# pythonImportsCheck — see pkgs/qcportal/default.nix for why.

# Reproduce the Python 3.14 build failure from gh_log.
repro-gh channel=default_channel:
    NIX_PATH=nixpkgs={{ nixpkgs_url }}/{{ channel }}.tar.gz \
      nix-build --no-out-link --show-trace \
        -E 'with import <nixpkgs> { overlays = [ (import ./overlays).qcfractal ]; }; python3Packages.qcportal'

# ---------------------------------------------------------------------------
# Formatting and linting.  These are also wired up as prek hooks by the flake;
# `just hooks` runs the same set the way a commit would.
# ---------------------------------------------------------------------------

# Format every tracked Nix file.
fmt:
    nixfmt $(git ls-files '*.nix')

# Check formatting without rewriting anything.
fmt-check:
    nixfmt --check $(git ls-files '*.nix')

# statix suggestions and deadnix dead-code detection.
lint:
    statix check .
    deadnix --fail .

# Run the prek hooks over the whole tree.
hooks:
    prek run --all-files
