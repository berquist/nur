---
name: no-daemon-check
description: How to run eval/instantiation checks in this repo when the Claude Code sandbox has no nix-daemon socket access — use whenever nix-build, nix flake check, or any store-realizing command is needed but unavailable.
---

# Checking this repo inside the Claude Code sandbox

The global `nix-sandbox` skill covers the sandbox itself: why nothing builds,
the chroot-store trap, why `<nixpkgs>` must come from `flake.lock` and not the
registry, and why every `nix flake` command fails on this repo (libgit2 and
`extensions.refstorage`).  Read it first.  This skill covers what is specific
to this repo.

**Use this repo's recipes, not the global skill's scripts.**  They do the same
thing and also know this repo's test suites and stubs.

## Everything at once: `just check-no-daemon`

`scripts/no-daemon-check.sh`.  In one pass it reports:

- every eval test in the suites named by `eval_suites` in the script, PASS or
  FAIL, with nothing built — each suite's `check` helper writes its verdict
  into the build command, which is what makes it readable without a daemon
- instantiation of every VM test in `tests/qcarchive/vm.nix`,
  `tests/aiida/vm.nix` and `tests/materials/vm.nix`
- instantiation of every test in `tests/dotdrop/`
- `nix-instantiate --parse` over every tracked `.nix` file

The run also prints the default `python3` of the nixpkgs it used.  This repo
follows that interpreter and pins none, so if the version is not what the
lock gives, the run is not checking what CI checks.

## One question: `just eval`

`scripts/sandbox-eval.sh`, the one-off counterpart, and the thing to reach for
while writing a derivation:

```sh
just eval vise.version                             # (import ./. { }).vise.version
just eval shakenbreak.makeWrapperArgs              # --strict, so lists print
just eval '(import <nixpkgs> { }).python3.version' # anything with a space is verbatim
```

Both scripts get their nixpkgs from `scripts/locked-nixpkgs.sh`.

## What only this repo needs

- **Psi4 is stubbed.**  The compute VM tests in `tests/qcarchive/vm.nix` need
  Psi4, which comes from the `nixos-qchem` flake input and is out of reach.
  The script passes a stub with `--arg psi4`; they only ever put it on the
  worker's PATH, so this checks their module config and test script, not that
  a real Psi4 builds.
- **`tests/harmonwig` is not covered.**  Its `pkgs` argument throws unless it
  gets the flake's composed package set, because cclib is a flake input.  Only
  `just harmonwig-tests` runs it, and that needs the daemon.
- **dotdrop is instantiated only.**  Those tests are real builds that run the
  packaged binary, so there is no verdict to read without a daemon.

## What stays user-side

`nix flake check`, `nix-build`, `just build`, `just ci`, `just check`,
`just harmonwig-tests` and every `just vm-test`.  Give the user the command.
