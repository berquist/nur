# Tests

`tests/default.nix` is a **dispatcher only** — it holds no tests. Each subdirectory owns one
subject, and `tests -A all` joins every non-VM suite. Adding a subject means a new subdirectory
plus two lines in the dispatcher; the per-suite `all` targets enumerate themselves, so there is
no list to remember to update.

```
tests/qcarchive/default.nix   eval tests for the QCFractal NixOS modules
tests/qcarchive/vm.nix        NixOS VM integration tests for the same
tests/aiida/default.nix       eval tests for the AiiDA NixOS module
tests/aiida/vm.nix            NixOS VM integration tests for the same
tests/cheminformatics/default.nix  eval tests for the two cheminformatics overlays
tests/dotdrop/default.nix     integration tests for the dotdrop package
tests/harmonwig/default.nix   integration tests for the harmonwig package
```

Five properties worth preserving, each explained at the code:

- The qcarchive and aiida suites stub their packages, so they cannot see overlay regressions.
  The `overlay-*` tests at the top of each file deliberately bypass the stubs — anything about
  how the modules *find* or *launch* their package belongs there.
- Their `check{}` helper bakes the verdict into the derivation's `buildCommand`, which is what
  lets `just check-no-daemon` report PASS/FAIL without building anything. It follows that
  nothing in those files may trigger import-from-derivation: read a `writeShellScript`'s `.text`
  rather than `builtins.readFile`-ing its store path.
- The VM tests are **not** reachable from `all` (KVM, minutes), and their `pkgs` must arrive
  already overlaid.
- `harmonwig` is not dispatched from `tests/default.nix` at all, and its `pkgs` argument throws
  rather than defaulting: its cclib comes from a flake input, so only the flake can build a
  working one. Reach it as `nix build .#checks.<system>.harmonwig`, or `just harmonwig-tests`.
- The cheminformatics suite tests packages it cannot build, and that is the point. Its
  `cclibStubOverlay` reproduces the *shape* of cclib's own overlay — an override of the
  top-level `python3` attribute — so that a `callPackage` reaching into the wrong package set is
  caught here, where it costs a second, rather than in a flake build that would need Psi4 first.
  A defaulted `cclib ? null` argument fails silently by design; something has to assert.

The eval suites are the fast loop and should stay that way. A new assertion about a module
belongs in `<subject>/default.nix`; only something that genuinely needs a booted system —
a service actually starting, a real calculation running — earns a place in `vm.nix`.
