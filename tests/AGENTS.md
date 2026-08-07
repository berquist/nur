# Tests

`tests/default.nix` is a **dispatcher only** — it holds no tests. Each subdirectory owns one
subject, and `tests -A all` joins every non-VM suite. Adding a subject means a new subdirectory
plus two lines in the dispatcher; the per-suite `all` targets enumerate themselves, so there is
no list to remember to update.

```
tests/qcarchive/default.nix   eval tests for the QCFractal NixOS modules
tests/qcarchive/vm.nix        NixOS VM integration tests for the same
tests/dotdrop/default.nix     integration tests for the dotdrop package
```

Three properties worth preserving, each explained at the code:

- The qcarchive suite stubs `qcfractal`/`qcfractalcompute`, so it cannot see overlay
  regressions. The `overlay-*` tests at the top of the file deliberately bypass the stubs —
  anything about how the modules *find* or *launch* their package belongs there.
- Its `check{}` helper bakes the verdict into the derivation's `buildCommand`, which is what
  lets `just check-no-daemon` report PASS/FAIL without building anything.
- The VM tests are **not** reachable from `all` (KVM, minutes), and their `pkgs` must arrive
  already overlaid.
