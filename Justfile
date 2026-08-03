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

nixpkgs_url := "https://github.com/NixOS/nixpkgs/archive/refs/heads"
default_channel := "nixpkgs-unstable"

# The nixPath matrix in .github/workflows/build.yml, in the same order.
channels := "nixpkgs-unstable nixos-unstable nixos-26.05"

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

# Build everything ci.nix reports as buildable and cacheable.
ci-build:
    nix shell -f '<nixpkgs>' nix-build-uncached -c nix-build-uncached ci.nix -A cacheOutputs

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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# Everything: eval tests, all six VM tests, and the pre-commit hooks.
check:
    nix flake check

# Evaluation tests only — fast, no VM, stubbed packages.
eval-tests:
    nix-build tests -A all --no-out-link

# One VM integration test, e.g. `just vm-test server-local-db`. Needs KVM.
vm-test name:
    nix build --no-link .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).vm-{{ name }}

# Drop into the interactive driver for one VM test.
vm-test-interactive name:
    $(nix-build tests/vm.nix -A {{ name }}.driver)/bin/nixos-test-driver

# The checks that do not need a nix-daemon: eval tests, VM test instantiation,
# and a parse of every Nix file. This is the whole of what runs inside the
# Claude Code sandbox.
check-no-daemon:
    ./scripts/no-daemon-check.sh

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

# Build one package the NUR way, e.g. `just build qcfractal`.
build pkg:
    nix-build -A {{ pkg }} --no-out-link

# Reproduce the Python 3.14 failure from gh_log: qcportal built against a
# channel's *default* interpreter rather than the python313 the repo pins.
#
# With the pin and the meta.broken marking in place this now stops at "Package
# is marked as broken". Set NIXPKGS_ALLOW_BROKEN=1 to push past that and see
# the original "TypeError: type 'Array' is not subscriptable" out of
# pythonImportsCheck — see pkgs/qcportal/default.nix for why.
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
