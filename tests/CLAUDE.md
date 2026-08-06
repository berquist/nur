# Tests

`tests/default.nix` is a **dispatcher only** — it holds no tests. Each subdirectory owns one
subject, and `tests -A all` joins every non-VM suite:

```
tests/qcarchive/default.nix   eval tests for the QCFractal NixOS modules
tests/qcarchive/vm.nix        NixOS VM integration tests for the same
tests/dotdrop/default.nix     integration tests for the dotdrop package
```

The VM tests are deliberately **not** reachable from `all` — they need KVM and take minutes.
Adding a new subject means a new subdirectory plus two lines in the dispatcher.

## `tests/qcarchive/default.nix` — pure evaluation

Runs `nixos/lib/eval-config.nix` with **stub** `qcfractal`/`qcfractalcompute` derivations
injected via `nixpkgs.overlays` (the only safe extension point, since `eval-config.nix` already
sets `nixpkgs.pkgs`). Each test is a `runCommand` that succeeds or fails on a boolean;
`assertFails` verifies module assertions throw by forcing `config.system.build.toplevel`.
**New tests must also be appended to the `all` `symlinkJoin` list** at the bottom — it is
hand-maintained.

Because those stubs replace the real packages, this file cannot see overlay regressions; the
`overlay-*` tests at the top deliberately bypass the stubs and check the real overlay instead.
Anything about how the modules find or launch their package belongs there, not in the stubbed
tests.

The `check{}` helper bakes the verdict into the derivation's `buildCommand`, which is what lets
`just check-no-daemon` report PASS/FAIL without building anything. Keep that property.

## `tests/qcarchive/vm.nix` — real NixOS VMs

`pkgs` must arrive **already overlaid**: `testers.nixosTest` uses the `pkgs` argument directly as
the node package set, so `nixpkgs.overlays` inside a node module is evaluated too late. The
default argument and the flake's `pkgs'` both handle this.

## `tests/dotdrop/default.nix` — integration, no VM

dotdrop is a plain CLI with no NixOS module, so these are `runCommand` builds rather than VM
tests. Unlike the qcarchive eval tests they **build the real package and run it**, so
`just check-no-daemon` can only instantiate them, not read a verdict.

Three tests, and the division of labour with upstream matters:

- `tests-ng` runs a **curated subset of dotdrop's own end-to-end shell suite** against the
  installed binary, via the `DT_BIN` environment variable every one of those 154 scripts
  honours. Without `DT_BIN` they fall back to `python3 -m dotdrop.dotdrop` over a source
  checkout, which would test upstream instead of our packaging. `file` and `diffutils` are
  deliberately **kept out** of the test's `PATH` so that this fails if the derivation's
  `makeWrapperArgs` ever stops supplying them — dotdrop's `dependencies_met()` and its
  `diff_command` validation both shell out and abort at startup without them.

  When adding a script to that list, check what the *script* shells out to, not just what
  dotdrop does. Several pick heavyweight example commands: `import-with-trans.sh` encrypts with
  `gpg`, which would mean a gpg-agent and a `GNUPGHOME` inside the sandbox for no packaging
  coverage at all — `transformations.sh` covers the same `trans_read`/`trans_write` path with
  `base64`. Anything not in `testTools` will fail with `command not found` deep inside a
  1500-line debug log.
- `roundtrip` is hand-written and reuses nothing from `tests-ng`, so it keeps working if
  upstream renames or drops the selected scripts.
- `metadata` checks the entry point, `--version` against the `version` attribute, the man page
  and all three shell completions.

The pytest suite under dotdrop's `tests/` already runs in the derivation's `checkPhase` (with
`HOME=$(mktemp -d)` — several of those tests write real dotfiles into `~`). It exercises the
Python API, not the CLI, and **no single pytest file covers import→install as a round trip**;
`tests-ng` is where upstream tests that, which is why it is worth running here at all.

Like the qcarchive suite, the `all` `symlinkJoin` list is hand-maintained.
