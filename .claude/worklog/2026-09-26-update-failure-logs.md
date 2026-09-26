---
date: 2026-09-26
slug: update-failure-logs
status: partial
sessions: ["92c82726-5832-441d-aef1-04f0efd8ee93"]
touches:
  - "scripts/update-packages.sh"
  - "Justfile"
  - ".gitignore"
  - "docs/version-updates.md"
  - "AGENTS.md"
---

# Keep what a failed package update learned

## Ask

1. > Figure out a better workflow for updating packages.  Right now, if a package update fails ("just update" or one of the commands that calls it), all of the information about the build is lost, such as what the new version/hash is and why the build failed.  I want to be able to iterate on the update+build+fix process, both with and without an agent.
2. > write the worklog

One decision was put to the user during planning: what happens to the rewritten
file when a bump's build fails under `--deliver=none`.  Options were keep it in
the tree, restore it and save a patch, or keep it for named packages but restore
it for batch runs.  Answer: **keep it in the tree**.

## Plan

## Context

`scripts/update-packages.sh` (behind `just update`, `update-from-scan`,
`update-all`, `update-pr`, `update-batch`) loses almost everything when a bump
fails:

- `nix-update --build` does the rewrite *and* the build in one call.  If the
  build fails, nix-update exits non-zero, `process_one()` records `failed`, and
  `process()` copies the snapshot back.  The new version and the new src hash
  are gone, and getting them back costs another download.
- The whole nix-update output goes into a shell variable.  Only
  `tail -n 3 | tr '\n' ' '` of it reaches the report.  The build log is not kept.
- The report lives in a `mktemp` directory that `main()` deletes.  Only a scan
  writes a JSON copy (`--json` from the `update-scan` recipe).

Goal: every attempt leaves a record on disk that a person or an agent can read,
and a failed bump stays in the tree, so the loop is *edit → rebuild → read log*
with no second nix-update.  In the sandbox the agent has no nix-daemon, so the
loop is: the user runs `! just update-rebuild X`, the agent reads the files.

## Design

### 1. One directory per attribute: `.scratch/update/<attr>/`

Written on every non-scan run, replaced at the start of the next attempt for
that attribute:

| File | What it holds |
|---|---|
| `result.json` | the report row (`attr, mode, old, new, status, detail`) plus `file` and `phase` (`nix-update`, `secondary`, `build`) |
| `nix-update.log` | the full nix-update output |
| `bump.patch` | `diff -u` of the snapshot against the rewritten file — the new version and hash, re-appliable with `git apply` |
| `build.log` | the full `nix build -L --keep-going` output (plus `refresh-hashes.sh` output when it ran) |
| `log-*` | per-derivation logs from `scripts/fetch-build-logs.sh -o <dir> build.log`, best effort |

Plus `.scratch/update/last-run.json`: the whole report, always written (not only
with `--json`).  Add `/.scratch/update/` to `.gitignore` beside the existing
`update-scan.json` line.

Scan mode writes none of this; it builds nothing and its product is already
`.scratch/update-scan.json`.

### 2. Split the rewrite from the build in `process_one()`

`scripts/update-packages.sh`:

- `nix_update_argv()`: stop adding `--build`.  nix-update then does lookup +
  rewrite + src hash only.  Output → `nix-update.log`.  A failure here keeps
  status `failed`, `phase: nix-update`.
- After the guards and `handle_secondaries()`, write `bump.patch`, then a new
  `build_bump()` when `build == true`:
  `nix build --no-link -L --keep-going --file "$repo_root" "$attr"`, tee'd to
  `build.log` (the same `--file` + locked `NIX_PATH` that `refresh-hashes.sh`
  already uses).
- Route `refresh-hashes.sh`'s stderr into `build.log` too, so a secondary
  failure is readable instead of printed and lost.
- On build failure: new status **`build-failed`**, `phase: build`,
  `detail` = the first `error:` line of the log rather than the last three
  lines.  Run `fetch-build-logs.sh` into the attr directory.
- Tree handling: under `--deliver=none`, set `keep_changes=true` on
  `build-failed` too, so the bump stays in the tree (your choice).  Under
  `commit`/`pr`, restore as now; `bump.patch` keeps the work.
- `tidy()` runs before the build, as now, so the kept file is formatted.

`attrs_from_report()` is unchanged: `build-failed` rows are not `would-update`,
so `update-from-scan` does not retry them by accident.

### 3. Rebuild without re-running nix-update

New flag `--rebuild ATTR...` in `update-packages.sh`: skip nix-update and the
guards, run `build_bump()` against the tree as it is, and rewrite
`result.json` (`updated` or `build-failed`) and `build.log`.  It keeps
`old`/`new` from the existing `result.json` when there is one.  No snapshot, no
restore — it never touches the file.

New Justfile recipe, one line, beside `update`:

```just
# Build a bump again after a fix, and record the result in .scratch/update/.
update-rebuild +pkgs:
    ./scripts/update-packages.sh --rebuild {{ pkgs }}
```

(`--jobs` is allowed with `--rebuild`; `--deliver` and `--scan` are refused.)

### 4. Progress and final table

`finished_status()` and `print_report()` already read rows back; add the
attribute directory path to the `build-failed` line on stderr, so the terminal
says where to look:
`[3/12] aiida-core: build-failed  2.7.1 -> 2.8.0  (.scratch/update/aiida-core/)`.

### 5. Documentation

- Header of `scripts/update-packages.sh`: replace "the report wants the last
  three lines of a failure" with a short section on the attribute directory and
  why the build is a separate step (nix-update's `--build` failure took the
  rewrite with it).
- `docs/version-updates.md` §5: the directory layout, `update-rebuild`, and the
  iteration loop; §6 item 3: "the report says so" now includes where.
- `AGENTS.md` "Where the explanations live" table: two rows pointing at the
  script header (where a failed bump's log goes; how to rebuild without
  re-running nix-update).

## Files

- `scripts/update-packages.sh` — the bulk of it
- `Justfile` — `update-rebuild` recipe
- `.gitignore` — `/.scratch/update/`
- `docs/version-updates.md`, `AGENTS.md` — pointers and the loop
- reused as is: `scripts/refresh-hashes.sh`, `scripts/fetch-build-logs.sh`,
  `scripts/locked-nixpkgs.sh`

## Verification

In the sandbox (no daemon):

- `shellcheck scripts/update-packages.sh` and `shfmt --diff` clean.
- `just update-policy` still works.
- `just update-scan qcportal` still writes `.scratch/update-scan.json` and
  creates no `.scratch/update/` directory.

On the host (needs daemon and network — you run these through `!`):

1. `just update <attr-that-moves>` for a package that builds: status
   `updated`, directory has `nix-update.log`, `bump.patch`, `build.log`.
2. Force a failure: bump a package, or add a failing line to a `preCheck`
   before `just update-rebuild <attr>`.  Expect `build-failed`, the file still
   dirty, `build.log` complete, `log-*` present, `result.json` with
   `phase: build`.
3. Fix it, `just update-rebuild <attr>` → `updated`.
4. `just update-pr <attr> --dry-run` path (via `./scripts/update-packages.sh
   --deliver=pr --dry-run <attr>`) with a failing build: tree restored,
   `bump.patch` present.
5. `prek run --files` on every changed file.

## Out-of-band

None.  The user ran no commands during the session.

## Changes

Committed by the user as `af6d86e` ("update-packages: keep what a failed bump learned").

- `scripts/update-packages.sh` — `nix-update` loses `--build` (and the
  `--help` probe for it); new `build_bump`, `save_patch`, `fetch_logs`,
  `first_error`, `attr_dir`, `rebuild_one`, `run_and_report`; `emit` writes
  `file` and `phase` and mirrors the row to `result.json`; `--rebuild` flag
  with its refusals; `build-failed` status; header section "A failed bump keeps
  what it learned".
- `Justfile` — `update-rebuild +pkgs`, one line, with a note on the loop.
- `.gitignore` — `/.scratch/update/`.
- `docs/version-updates.md` — §5 gains the directory layout and the loop; §6
  item 3 says where the log is.
- `AGENTS.md` — two rows in "Where the explanations live", one line in
  Commands.  (`CLAUDE.md` is the symlink; the edit had to go to the target.)

## Outcome

Implemented as planned, with two small departures:

- A failure in `handle_secondaries` is `build-failed` with `phase: secondary`,
  not `failed`.  `refresh-hashes.sh` builds the whole attribute to read its
  hashes, so a check phase failing there is a failed build, and it gets the same
  keep-in-tree treatment.
- `--rebuild` resolves no policy at all.  It takes `old` from the previous
  `result.json` and evaluates `new` with `nix eval <attr>.version`, so an
  attribute that does not exist is reported by `nix build` in `build.log`.

Verified in the sandbox: `shellcheck` and `shfmt --diff` clean; the four
`--rebuild` refusals fire; `--policy qcportal` still works and creates no
`.scratch/update/`; `just --list` shows `update-rebuild`.

**Not verified**, because the sandbox has no nix-daemon and no `nix-update`:
any real bump, build, `--rebuild`, the `commit`/`pr` restore path, the
`fetch-build-logs.sh` call, and `prek` (devShell only).  Hence `status: partial`.

Considered and not taken:

- Timestamped run directories (`.scratch/update/runs/<ts>/<attr>/`) with a
  `latest` link.  Latest-attempt-only is enough for iterating, and each
  attempt removes its own directory first so no stale file is mistaken for
  fresh.
- Leaving `nix-update --build` in place and only saving its output.  The
  rewrite would still be lost on a failed build, which is the core complaint.

## Follow-ups

- On the host: `just update <attr>` for one package that builds and one that
  does not; `just update-rebuild <attr>` after a fix;
  `./scripts/update-packages.sh --deliver=pr --dry-run <attr>` with a failing
  build (file restored, `bump.patch` kept); `prek run --files` over the five
  changed files.
- Check that `first_error` picks a useful line from a real failed `-L` log; if
  it lands on a dependency's noise, prefer the `builder for '…' failed` line.
- Repeated commands: only the `export PATH="$(scripts/sandbox-path.sh)"`
  prefix recurred, which is sandbox scaffolding already documented; nothing to
  make permanent.
