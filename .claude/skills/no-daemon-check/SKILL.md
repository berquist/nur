---
name: no-daemon-check
description: How to run eval/instantiation checks in this repo when the Claude Code sandbox has no nix-daemon socket access — use whenever nix-build, nix flake check, or any store-realizing command is needed but unavailable.
---

# Working inside the Claude Code sandbox

The sandbox blocks `socket(AF_UNIX)`, so `nix` cannot reach the nix-daemon: every store
operation dies with `cannot create Unix domain socket: Operation not permitted`. Nothing can be
built or realised from inside it, and `nix flake check` / `nix-build` are unavailable — ask the
user to run those.

Evaluation *is* possible, which is enough to catch module, overlay, and test-script errors —
most of what actually breaks here.

**Run `just check-no-daemon` (i.e. `scripts/no-daemon-check.sh`) rather than reassembling the
incantation.** It sets up the chroot store and reports, in one pass:

- every eval test in `tests/qcarchive/`, PASS/FAIL, without building any of them
- instantiation of all six VM tests in `tests/qcarchive/vm.nix`
- instantiation of every test in `tests/dotdrop/`
- `nix-instantiate --parse` over every tracked `.nix` file

The mechanics it encapsulates, if you ever need them directly:

```sh
export XDG_CACHE_HOME="$TMPDIR/nix-cache"   # ~/.cache is a read-only tmpfs
export NIXPKGS_CONFIG=                      # /etc/nix/nixpkgs-config.nix is outside the store
# The locked nixpkgs, located without the network: a flake input lands in the
# store as a fixed-output path (recursive sha256, name "source"), so flake.lock's
# narHash determines where it is.
narhash=$(jq -r '.nodes.nixpkgs.locked.narHash' flake.lock)
export NIX_PATH=nixpkgs=$(nix-store --print-fixed-path --recursive sha256 \
  "$(nix-hash --to-base16 --type sha256 "${narhash#sha256-}")" source)
nix-instantiate --store "$TMPDIR/nixstore" tests/qcarchive/vm.nix -A server-local-db
```

Four traps the script already handles:

- A chroot store starts empty, and even `--eval` refuses to read a `/nix/store/…` path that is
  not registered in it. `tests/qcarchive/default.nix` reaches into
  `<nixpkgs>/nixos/lib/eval-config.nix`, so a bare `--eval` fails with
  `path '…-source' is not valid` until an **instantiation** has copied the source in.
  Instantiate first, then evaluate.
- The three compute VM tests need Psi4, which comes from the `nixos-qchem` flake input and is
  out of reach. Pass a stub with `--arg psi4` — they only ever put it on the worker's PATH.
- `NIX_PATH` normally points at `flake:nixpkgs`, which needs the network. **Resolve it from
  `flake.lock`, not from `/etc/nix/registry.json`.** The registry copy is whatever the sandbox
  image carries and trails the lock — in Aug 2026 its `python3` was 3.13 while the lock's was
  3.14 — so everything the python313 pin exists to catch (the `meta.broken` markings, any
  `pkgs.python3.withPackages` reaching a qcportal dependant) passes against the registry and
  fails in `nix flake check`. That is how the `compute-singlepoint` breakage survived a clean
  local run. The script prints which source it used and the resulting default `python3`
  version; if that version is not the lock's, the run is not checking what CI checks.
- Do not reach for `nix flake …` to find the locked input — libgit2 in the sandbox refuses to
  open this repo at all (`unsupported extension name extensions.refstorage`), so every flake
  command, including `nix develop`, fails before it starts.

`--store dummy://` also works for `--eval`, but cannot instantiate derivations.

What the sandbox *cannot* do: build or realise anything, boot a VM, or resolve new flake inputs
(`nix flake lock` needs the network). `nix flake check`, `nix-build` and `just ci` are all
user-side.
