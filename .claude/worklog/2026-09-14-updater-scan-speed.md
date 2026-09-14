---
date: 2026-09-14
slug: updater-scan-speed
status: done
sessions: ["51ac5bb0-eae6-4576-abc7-f23ab2ef8d31"]
touches:
  - "scripts/update-packages.sh"
  - "scripts/update-universe.nix"
  - "scripts/refresh-hashes.sh"
  - "Justfile"
  - "docs/version-updates.md"
  - "pkgs/parsl/**"
  - "pkgs/firecrest-streamer/**"
  - "pkgs/fairchem-core/**"
  - "pkgs/fairchem-data-oc/**"
  - "pkgs/fairchem-data-omat/**"
  - "pkgs/fairchem-data-omol/**"
---

# `just update-scan`: 57 minutes to 16 seconds, and a guard against the bumps it was offering

## Ask

> read "update-scan.log".  This is the output of "just update-scan". as part of the updater plan.
> Two things: 1. it's very slow, as you can see by the time output.  Is there any way to speed it
> up?  2.  How do I apply these updates? Now that the scan is done, all of that work is
> effectively lost unless I save the log and go update everything by hand.

> do 1 and 2, then re-run the scan

> read "update-scan-2.log"

> just update-scan --json=update-scan.json 2>&1  29.70s user 8.23s system 237% cpu 15.978 total
> tee update-scan-2.log  0.00s user 0.00s system 0% cpu 15.978 total

> do 3 and 4, then the worklog

## Plan

Plan mode was never entered; the plan was a four-item proposal answering the two questions, and
the user took it in two halves — 1 and 2, then 3 and 4.

1. `scripts/update-packages.sh` — scan adds `--no-src`; drop `--flake` for `--file ./default.nix`
   with `NIX_PATH` exported; `--jobs=N` parallel workers with per-worker report files;
   `--from=FILE`.
2. Version-regression guard next to `unstable_date`.
3. `scripts/update-universe.nix` — `versionRegex` and `url` policy fields; annotate the fairchem
   three and `parsl`.
4. `Justfile` — `update-scan` writes `.scratch/update-scan.json`; add `update-from-scan`.

## Out-of-band

The user ran the scan in a separate terminal both times, so only what they pasted back is
recoverable. The first run's timing came from `update-scan.log`:

```
just update-scan  353.96s user 374.17s system 21% cpu 57:23.82 total
```

and the second from a pasted prompt:

```
just update-scan --json=update-scan.json 2>&1  29.70s user 8.23s system 237% cpu 15.978 total
```

`tee` swallowed the `time` line on the second run — `2>&1` applies to `just`, not to the shell's
own `time` builtin — which is why it had to be pasted separately. Running these through `!` in
the prompt would have put both in the transcript.

The Claude Code sandbox has no nix-daemon socket, so nothing that realises a store path could be
run from inside it. What *did* work, and is worth reusing: `nix-instantiate --eval --store
dummy://` over `nix_update`'s own `eval.nix`, which is how the non-flake path was measured at
0.165 s and how the four unresolvable attributes were proved resolvable before any change was
made.

## Changes

### The diagnosis, which came from reading nix-update 1.16.0 rather than the log

Three separate costs, found in `/nix/store/…-nix-update-1.16.0/…/nix_update/`:

- `dependency_hashes.py:73` — a src hash is recovered by building the fetcher with
  `outputHash = ""` and parsing the *failure*. A failed fixed-output derivation leaves nothing in
  the store, so every moving package downloaded its whole source and discarded it. The scan was
  not warming a cache; it was pure waste.
- `options.py:101` — `get_flake_store_path()` runs `nix flake metadata --json` and "always
  re-copies the flake", and `get_flake_import_path()` is called more than once per invocation.
  Then `getFlake` evaluates flake.nix through flake-parts to reach one attribute.
- 21 % CPU utilisation over 57 minutes: four fifths of the wall clock was waiting on forges,
  serially.

And one bug the log had been reporting as eight upstream failures: `eval.nix:49-57` looks the
attribute up in `flake.packages.${system}` and then in the flake root, **never in
`legacyPackages`**. So exactly the four attributes that are not top-level derivations —
`internalPackages.chemfiles`, `internalPackages.trexio`, `python313Packages.monty`,
`python313Packages.tensorpotential` — could not be resolved at all.

### `scripts/update-packages.sh`

- `nix-update --file "$repo_root"` rather than `--flake`, with a new `pin_nixpkgs` exporting
  `NIX_PATH` from `locked-nixpkgs.sh` — mandatory, not cosmetic: `default.nix` resolves `pkgs`
  through `<nixpkgs>`, so without it a bump is evaluated and built against whatever the registry
  holds.
- `--no-src` in scan mode.
- `--jobs=N`, one per core capped at 8 in scan mode and 1 elsewhere, refused outside `--scan`.
  `shared_positions` drops back to one worker if two actionable attributes ever claim one file.
- `emit` writes one file per attribute into a temp directory; `report_json` cats it back.
- Change detection is `cmp` against the snapshot, not `git diff` — `git diff` refreshes the index
  and so takes `.git/index.lock`, which a dozen workers collide on, and it also reported every
  package in an already-dirty file as moving.
- `version_regression` / `version_prefix`, the second guard.
- `--from=FILE` and `attrs_from_report`, reading a previous `--json` report's `would-update` rows.
- `apply_rev_from` moved to `nix build --file` for the same reason as the driver.

### `scripts/refresh-hashes.sh`

Moved to `nix build --file` and given a NIX_PATH fallback. This was a latent bug the `--file`
change *exposed*: `internalPackages.trexio` declares a `secondary` source, and
`nix build .#internalPackages.trexio` names nothing. It had never been reachable, because the
attribute failed at eval before it could get there.

### Policy and packages

- `scripts/update-universe.nix` — `versionRegex`, read from `passthru.updatePolicy`.
- The four `fairchem-*` packages each declare their own tag series. The monorepo tags thirteen
  distributions out of one release feed, so all four were offered `fairchem_data_omol-0.1.2` and
  refused it as unparseable.
- `pkgs/firecrest-streamer` — `mode = "report"`.
- `pkgs/parsl` — `fetchurl` to `fetchPypi`. Same bytes, same store path, no rebuild.

### Justfile and docs

`update-scan` writes `.scratch/update-scan.json` unconditionally; `update-from-scan` and
`update-from-scan-pr` read it back. `.gitignore` takes the report path alone rather than all of
`.scratch/`. `docs/version-updates.md` §3 gains the `--file` rationale, §4 the version guard and
`versionRegex`, §5 the speed table and the report pair. `AGENTS.md` gains ten pointer rows.

## Outcome

**57:23.8 → 15.98 s wall, 728 s → 37.9 s CPU, 21 % → 237 % utilisation.** Same 147 attributes.

| | before | items 1–2 | items 3–4 |
|---|---|---|---|
| current | 73 | 76 | 78 |
| would-update | 47 | 35 | 35 |
| rejected | 5 | 18 | 17 |
| skipped | 14 | 14 | 15 |
| failed | 8 | 4 | 2, then 0 once the releases API replaced the feed |

The version guard fired on exactly the twelve packages predicted from the first log, and on
nothing else: `aiida-core`, `ase-db-backends`, `chemfiles`, `fairchem-data-oc`, `maml`,
`mdanalysis`, `mongomock-persistence`, `pydefect`, `pyfhiaims`, `redun`, `vise`, `xyzgraph`.

**The scan had been offering roughly a third of its bumps as regressions, and nothing was
checking.** That is the finding that mattered more than the speed. A dozen packages here carry a
hand-written version because upstream's newest tag is years behind its default branch — `vise`
827 commits past v0.1.13, `pydefect` 764 past v0.2.6 — so `nix-update` reads the tag and writes
it over the real version. `just update $(jq … would-update)` before this change would have
downgraded twelve packages.

### Rejected, and why

- **`url` as a policy field, which was in the proposal and is not in the tree.** It would have
  moved `parsl` from one `failed` row to a different one. `--url` only redirects version
  *detection*; the hash step still rebuilds `.src` from the derivation's own fetcher, and
  pythonhosted addresses a file by a hash of its contents, so the new version's URL would 404.
  `fetchPypi` fixes both halves. No other package wanted the field, so it was not added.
- **`versionRegex` for `firecrest-streamer`.** There is no streamer tag series to match; the
  repository's tags version the FirecREST server. `report` is the honest answer.
- **Parallelism outside scan mode.** `--deliver` drives git and `--limit` is a running count.
  The apply path's cost is builds — hours — so racing the driver saves minutes out of hours and
  risks a half-pushed bump.
- **`git worktree` for scan mode** was already rejected by the script's own header, and nothing
  here changed that.
- **A batch-by-file scheduler** for the shared-position case. Detect and fall back to serial is
  proportionate; nothing shares a file today.

### `releases.atom` is a window, not a list — caught by re-running the scan

The prediction that item 3 would clear all four `failed` rows was wrong, and re-running is what
showed it. `fairchem-core` and `fairchem-data-omol` went `current`; `parsl` went
`would-update 2026.7.27 -> 2026.9.7`, which is the fetcher change working; `firecrest-streamer`
went `skipped`. But `fairchem-data-omat` and `fairchem-data-oc` failed *differently* — "No
version matched the regex", listing `fairchem_core-2.18.0`, `fairchem_lammps-0.5.0`,
`fairchem_core-2.17.0`.

`nix-update`'s default fetcher reads `releases.atom`, which carries only the newest handful of
releases. With thirteen distributions tagging into one feed, a series that has not released
lately is absent from it altogether — `fairchem_data_omat`'s tag is from 2025-11-14. The two
that passed did so only because they were inside the window that week, which is an intermittent
failure waiting for a quiet month, not a working configuration.

So `versionRegex` now also passes `--use-github-releases`, which walks the paginated API
(`DEFAULT_RELEASES_LIMIT = 1000`, honours `GITHUB_TOKEN`) and threads through to branch mode.
Implied rather than made a second policy field, because the two conditions are one condition: a
regex is declared exactly when a repository has several series in one feed.

### Verified

The final scan is **79 current, 36 would-update, 17 rejected, 15 skipped, 0 failed** over 147
attributes in 16 seconds. `fairchem-data-omat` reads `current 0.2.0`, which confirms its own
note — nothing but copyright headers has touched that subtree since the tag — and
`fairchem-data-oc` takes a clean six-day snapshot with its own version prefix intact.
`parsl 2026.7.27 -> 2026.9.7` is the one genuinely new bump the exercise surfaced, as opposed to
one that was merely slow to find.

Every `failed` row in the original log turned out to be a defect on this side: four were an
addressing bug, two a feed-window assumption, one a fetcher that hid the version, and one a
package that should never have been in `stable` mode.

`nixfmt`, `statix`, `deadnix` and `prek` passed over items 1–4. They have not been run over the
`--use-github-releases` change, which touches one shell file, two Nix comments and two documents.

## Follow-ups

- `just hooks` has not seen the `--use-github-releases` change.
- `firecrest-streamer` and `parsl` aside, `lwreg 0.2.0 -> 2024.08.1` and `sevenn 0.13.0 ->
  0.13.1.cp` pass both guards and have not been judged. Probably correct — upstream moved to
  CalVer in one case — but nobody has looked.
- There is no mode for "follow the branch, keep the version", which is what `firecrest-streamer`
  actually wants. `report` means its rev is now manual. Worth adding if a second package needs it.
- `scripts/channel-gaps.sh` has a pre-existing `shfmt --diff` complaint (two pipe continuations),
  untouched here because it was out of scope.
- **Capturing repeated commands**: `scripts/sandbox-path.sh` was invoked at the head of every
  Bash call this session — around twenty times — because the sandbox starts with almost nothing
  on PATH. That is not a project workflow step, so it is not a `just` recipe; the right home is
  `.claude/settings.local.json` or a session-start hook that exports it once. `shellcheck` +
  `shfmt --diff` over a script also recurred, but the prek hooks already cover it.
