---
date: 2026-09-25
slug: moyopy-backport
status: partial
sessions: ["34f148c0-f181-40d2-ad45-19b2193e7eb7"]
touches:
  - "pkgs/moyopy/**"
  - "pkgs/pymatgen-core/**"
  - "overlays/default.nix"
  - "default.nix"
  - "scripts/update-universe.nix"
  - "tests/chemtools/default.nix"
  - "AGENTS.md"
---

# moyopy: backport 0.17.0 for nixos-26.05

## Ask

1. read "log-python3.13-pymatgen-core-2026.9.23-rhlfxzvb4zpm4p9ym3wmfjk4jay0rjim"
2. 1. read "log_ci_matrix" to determine; if no relevant output is present, the answer is yes  2. what should "<26.05 nixpkgs>" in the command be replaced with? give me something I can put directly in the shell
3. the answer is 0.9.0
4. A, I cloned it into wc/moyo at the v0.17.0 tag
5. got: sha256-x2UMZcTT8nSzHX+MI60+FJnpOLEBvdVWVqNo8p/BXZQ=
6. I ran it and nothing happened: $ NIX_PATH=$(scripts/locked-nixpkgs.sh) nix build --impure --no-link -L --expr '(import ./. { }).python3Packages.callPackage ./.scratch/moyopy.nix { }'
   NIX_PATH=nixpkgs=/nix/store/zk79px3awmq1lhqg1p0i5c3ny0cw8sy7-source [flake.lock]
7. error: build log of '' is not available
8. still nothing
9. (pasted: the `nix eval … .drvPath` / `nix build --print-out-paths` / `echo "exit: $?"` output, reproduced under Out-of-band)
10. approved, apply them
11. write the worklog

## Plan

No plan mode.  The plan was the choice between three options, offered after the
cause was found; the user chose A.

| Option | Result on 26.05 |
|---|---|
| **A. Backport moyopy ≥ 0.17**, guarded like `monty` and `qcelemental` | correct answers; full sweep runs |
| B. Deselect the three node ids when `moyopy.version < 0.17` | tests pass, the `symmetry` extra still ships wrong answers |
| C. Drop moyopy from the extra and the check inputs when < 0.17 | the moyopy backend is absent; the sweep skips |

The change spanned seven files, so it went through the `patch-review` skill:
`.scratch/moyopy.nix` (the new derivation) and `.scratch/moyopy-wiring.diff`
(everything else), reviewed, then applied.

## Out-of-band

- `nix eval --raw github:NixOS/nixpkgs/nixos-26.05#python3Packages.moyopy.version`
  → `0.9.0`.  The locked nixpkgs has 0.18.0.
- The first build of `.scratch/moyopy.nix` against `lib.fakeHash` gave the
  `cargoDeps` hash `sha256-x2UMZcTT8nSzHX+MI60+FJnpOLEBvdVWVqNo8p/BXZQ=`.  The
  user put it into the scratch file.
- The later build, eval and exit-status check:

  ```
  /nix/store/cwff2wxsvmxkri7r3lb9x449srywdl6p-python3.14-moyopy-0.17.0.drv
  /nix/store/yzx76nypfc0986fgj98s9jq66zwjk7g3-python3.14-moyopy-0.17.0
  exit: 0
  ```

These commands ran in a separate terminal and their full output is not in the
transcript.  Only what the user pasted is recorded.

## Changes

All in `bca2da4 moyopy: backport 0.17.0 for nixos-26.05`.

- `pkgs/moyopy/default.nix` — new.  nixpkgs' 0.18.0 derivation at the
  v0.17.0 tag (the floor, not the newest).  Licence `[ mit asl20 ]` from
  pyproject's `MIT OR Apache-2.0`.  `updatePolicy.mode = "report"`.
  `test_interface.py` stays disabled: it imports pymatgen, which takes moyopy as
  a check input.
- `overlays/default.nix` — a `moyopy` binding after `monty` in the materials
  overlay: `psuper.moyopy` when `>= 0.17`, else ours.
- `tests/chemtools/default.nix` — `materials-moyopy-satisfies-pymatgen-core`,
  and `moyopy` in `internalDependencies`.
- `scripts/update-universe.nix` — `python3Packages.moyopy` in `extras`, or the
  every-`pkgs/`-directory-is-reachable check fails.
- `default.nix`, `AGENTS.md` — the counts of packages outside the top-level rule
  (five → six, seven → eight), a Deferred-packaging row, a pointer row.
- `pkgs/pymatgen-core/default.nix` — a comment at `symmetry = [ moyopy ];`.

## Outcome

**Cause.**  On nixos-26.05 only, `pymatgen-core` failed 3 of 3239 tests, all
`test_symmetry_dataset_backends_agree_on_semantics[42|65|69]`.  Same space-group
number from both backends, different Wyckoff letters (`c`/`d`, `n`/`o`,
`m`/`o`).  Upstream's own pyproject states the reason beside `moyopy>=0.17`:
0.3–0.16 disagree with spglib on some groups.  26.05 has 0.9.0.  The build did
not catch it because moyopy is only in extras and check inputs, and
pythonRuntimeDepsCheckHook reads neither.  So this is a wrong answer shipped in
an extra, not a flaky test — which is why B was rejected.

**Verified:** moyopy 0.17.0 builds and its suite passes on the locked nixpkgs
(Python 3.14); `just check-no-daemon` passes (chemtools 14/14); `just
update-policy` reports `python3Packages.moyopy` as `external` 0.18.0 on the
locked nixpkgs, which is the guard working; `prek` passes on every changed file.

**Not verified:** the 26.05 leg itself.  That is the point of the change, hence
`status: partial`.

**Dead ends worth not repeating:**

- The build after the hash was filled in printed nothing.  That was success:
  `nix build --no-link` is silent when the output already exists.
  `--print-out-paths` plus `echo "exit: $?"` is the command that says so.
- `nix log --impure --expr '…'` failed with `build log of '' is not available`:
  it did not resolve the expression to a derivation.  `nix log <drv path>` also
  had nothing, because the output predated those commands and no log was kept.
  A green `pytestCheckHook` build is still evidence that tests ran, since pytest
  exits 5 on an empty collection.
- The eval helper cannot select a channel, so a 26.05 version has to come from
  the host: `nix eval --raw github:NixOS/nixpkgs/nixos-26.05#…`.  That is the
  same branch head `.github/workflows/build.yml` uses.
- **`rm -rf .scratch` deleted five tracked files** (`.scratch/nixpkgs-*.patch`,
  which `AGENTS.md` points at).  The `patch-review` skill's cleanup step assumes
  `.scratch/` is its own.  Restored with `git restore -- .scratch`.

## Follow-ups

- Run `just ci nixos-26.05` and confirm `pymatgen-core` passes the backend sweep.
- Delete `pkgs/moyopy` and its binding once 26.05 leaves `channels`.
- **Proposal — the `patch-review` skill:** in its cleanup step, remove only the
  files it wrote, not the whole directory.  In this repo `.scratch/` holds
  tracked files.  It is a user-level skill, so this is your change to make.
- **Proposal — sandbox PATH:** almost every Bash call this session began with
  `PATH="$(scripts/sandbox-path.sh)"; export PATH`, and the first four calls
  failed without it.  A `SessionStart` hook that exports it once, in
  `.claude/settings.local.json`, would remove the prefix.
- **Proposal — hooks in the sandbox:** `nix develop` fails here (`unsupported
  extension name extensions.refstorage`), so `prek` is not on PATH.  The store
  `prek` works with `PREK_HOME="$TMPDIR/prek"`.  This could go in
  `scripts/no-daemon-check.sh` or the `no-daemon-check` skill.
