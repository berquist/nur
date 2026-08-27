---
date: 2026-08-26
slug: pollution-lottery
status: done
sessions: ["7b325d81-322b-4993-8eae-1949aa650d72"]
touches:
  [
    "pkgs/pytray/**",
    "pkgs/aiida-core/**",
    "tests/aiida/ordering.nix",
  ]
---

# The pollution lottery, and a harness that stops sampling it

## Ask

Verbatim and in order. No plan mode was used, so there is no `## Plan` section — the work was
driven one prompt at a time, each one a log file to read.

> Read "0.txt" for a failure from GitHub. I don't know how to replicate it locally because "just
> ci-matrix" is clean (see "log_ci_matrix").

> read "log-aiida"

> "log_check", "log_tests", and "log_ci_matrix" all pass. is aiida done?

> yes

> "log_check", "log_tests", and "log_ci_matrix" all pass. is aiida done?

> do the adversarial ordering run

> Both "log-archive-comments-user" and "log-ordering-all" look ok

> "log-aiida" show that this worked

> run the control for group-agroup

> read "log-unguarded"

> read "log-unguard-all"

> yes, write the worklog

## Out-of-band

Every build in this session was run by the user in a separate terminal, and **had to be**: the
Claude Code sandbox has no nix-daemon socket, so `!` — which runs in that same sandbox — cannot
build either. There is no way to make these recoverable from the transcript. The log files the
user redirected to are the whole record, and they are untracked. What follows is reconstructed
from their contents.

| Log | What it was | Result |
| --- | --- | --- |
| `0.txt` | GitHub Actions job, `just ci-build` | red — `pytray` |
| `log_ci_matrix`, `log_check`, `log_tests` | the three local suites, twice each (before and after the aiida guards) | green throughout |
| `log-aiida` (first) | `nix build` of aiida-core | red — `newuser@new.n` |
| `log-ordering-all` | `nix-build tests/aiida/ordering.nix -A all` | green, 15/15 collected |
| `log-archive-comments-user` | single entry, one minute later | cache hit, three lines, no signal |
| `log-aiida` (second) | the first negative control, guard hand-reverted | red, 2 failed 1 passed |
| `log-unguarded`, `log-true-agroup` | `--arg unguard true -A group-agroup` | red, 1 failed 1 passed |
| `log-unguard-all` | `--arg unguard true -A all --keep-going` | all seven red |

Two log files carried no information and were nearly read as though they did. `log_tests` builds
one derivation (`nur-tests.drv`) against stubbed packages and never touches aiida-core.
`log-archive-comments-user` was a cache hit from the `all` run sixty seconds earlier.

## Changes

- `pkgs/pytray/default.nix` — `disabledTests = [ "test_task_cancel" ]`.
- `pkgs/aiida-core/default.nix` — six more `aiida_profile_clean` hunks in `postPatch`, across four
  test files, plus the reasoning above the block.
- `tests/aiida/ordering.nix` — new. Seven adversarial-ordering checks and the `unguard` negative
  control.
- `tests/aiida/isolation.nix` — new. Every test module in a session of its own, for the mirror-image
  bug: a test that quietly needs a neighbour to have run first. One derivation looping over ~200
  modules rather than 200 rebuilds of aiida-core.
- `tests/aiida/pollution-scan.nix` + `scripts/aiida-pollution-scan.py` — new. The three static scans
  used in this session, made re-runnable. The derivation exists so the scan sees the **patched**
  tree; run against upstream source it would re-report all twelve hazards this repo has fixed.
- `Justfile` — `aiida-ordering`, `aiida-ordering-control`, `aiida-isolation`, `aiida-pollution-scan`.

None of the three harnesses is wired into `tests/default.nix`, for the same reason `vm.nix` is not:
they build real packages and take minutes to hours.

Commit state at the end of the session: the two package fixes landed as `037f490`, whose message
still carried a `--cores 8` recommendation that was later measured and withdrawn. Everything after
it — the three harnesses, the `Justfile` recipes, this worklog — is **staged but uncommitted**,
against an amend of that commit with the corrected message in `.git/worklog-commit-msg.txt`:

```sh
git commit --amend -F .git/worklog-commit-msg.txt
```

If a later session finds a staged tree here, that is what it is for. Nothing is half-applied: the
guards are in place (`aiida-core` evaluates to `a7qc0mac…`, the guarded derivation), and the
`unguard` control is an argument rather than an edit, so no revert is ever left behind.

## Outcome

### Why a green `ci-matrix` proved nothing

The GitHub failure was `pytray`'s `test_task_cancel`. `just ci-matrix` was clean locally for a
reason that had nothing to do with the bug: the *exact* failing derivation
(`hhyyybpm77hm9g8q12736rrd30yd7aln`) was already realised in the local store, so `nix build` saw a
valid output and did nothing. The local log ends on the bare `ci-build` command line with no output
under it, and the word "pytray" appears in it zero times.

The test is an upstream race with a sub-microsecond window — `run_coroutine_threadsafe` onto a loop
in another thread, then `.cancel()` on the concurrent future, asserting the coroutine never ran.
Measured on this machine by running the test body from the sdist:

| sleep between submit and cancel | cancel loses |
| --- | --- |
| none | 0/100 |
| 1 µs | 94/100 |
| 100 µs | 100/100 |

Unpinned, 0/300. Pinned to one CPU with `taskset -c 3`, 1/300 with no other load. A four-core
runner mid-`--keep-going` loses it; a 128-core idle box does not. Nothing to retry against and no
dependency to supply, so the test is disabled.

### The same shape, six more times, in aiida-core

`log-aiida` was one failure in 3363: `test_nodes_belonging_to_different_users` dying on its *first*
statement with `uq_db_dbuser_email … Key (email)=(newuser@new.n)`. Three tests under
`tests/tools/archive/orm/` create that hardcoded user, all three call `reset_storage()` **mid**-test
and then `import_archive()` on an archive that carries the user back, so each one ends with the row
in place. Two defend themselves with `aiida_profile_clean` at setup. The third asked for bare
`aiida_profile` and was the only one left open.

Rather than wait for the next draw, the suite was scanned for the shape: a **literal** written into
a **UNIQUE** column, kept only where some other test creates the same literal and at least one of
the two does not clean. That found the five already patched plus five more, all confirmed to
`.store()` their row.

The scan re-run against a fully patched tree now reports zero unguarded victims. The four entries it
still flags are polluters that cannot themselves be victims — three sit in the module whose autouse
`groups` fixture deletes every group at setup, and `test_querybuilder.py` is never collected because
`test_query` is a substring of `test_querybuilder`. That last one was checked rather than asserted:
the module appears zero times in `log_check`.

### What the scan cannot see, and why "done" was never claimed

One shape is modelled. The repo's own patch history holds four others that this scan would never
find: deliberately corrupted state (`test_get_unreferenced_keyset` → `test_backup`), shared relative
filenames in `/build/source` (`TestLaunchersDryRun`, `test_profile_access.py`), ordering against
cached globals (`test_fallback_workflow_tools_on_loading_error`), and — the one that closes the door
on scanning — rows that arrive inside a fixture archive. `testing2` appears nowhere under `tests/`;
it rode in inside an `aiida-export-migration-tests` archive, so no reader of test source can see it.

### The harness, and the two ways it nearly became worthless

Four green suite runs are worth about nothing against a 1-in-128 draw per pair, so the pairs were
turned into builds. Rejected on the way there:

- **Serial whole-suite.** The obvious "just run it with one worker" is already documented as broken
  above `postPatch` — `dontUsePytestXdist` over the whole suite hangs in
  `tests/engine/test_launch.py` until pytest-timeout's 240 s fires. Serial is safe only for a
  handful of node ids that avoid that module, which is what `ordering.nix` does.
- **Turning the worker count down to sample harder.** Proposed, then measured and withdrawn. The
  argument was that two tests co-locate with probability 1/W, so fewer workers means more
  collisions. That ignores the other half: a worker holding both also holds the tests *between*
  them, and 12% of this suite (318 of 2753) resets the profile at setup. Real behaviour is
  `P ~ (1/W)·0.88^(d/W)`, so for a cross-directory pair (d ~ 2000) the numbers run 8 → ~0%,
  128 → 0.106%, 256 → 0.144%, 512 → 0.119%. **128 is already near the optimum**; 8 detects
  nothing, because it gives the pollution time to be cleaned up. The sampling lever is spent —
  which is the real argument for the deterministic harness.

Two mistakes were caught before they shipped, both of the same kind — a harness that looks right and
proves nothing:

1. `doInstallCheck = false` on the overrides. In this nixpkgs `buildPythonPackage` runs pytest in
   the **installCheckPhase** (`doCheck=""`, `doInstallCheck="1"` on the base derivation), so that one
   line would have disabled every check and turned all seven entries green vacuously.
2. The two-line anchor for the `test_users.py` inverse, written as an indented `''` string. `''`
   strips the common leading whitespace, which would have left the first line flush and the second
   indented, matching nothing. Written with an explicit `\n` instead.

The first negative control was run by hand-reverting a hunk, and the block was **deleted rather than
commented**, leaving the tree unguarded afterwards — caught by the derivation hash moving to
`2pbh61lk…` and restored to `a7qc0mac…`. That is why `unguard` exists as an argument: it appends the
inverse *after* the package's own `postPatch` instead of removing anything from it, so nothing needs
restoring, and `--replace-fail` turns any future drift in the patch text into a build error rather
than a silent no-op.

### Verdict

All seven entries green normally; all seven red under `--arg unguard true`, each with the polluter
passing and only the victim failing, across both constraints:

| Entry | Key |
| --- | --- |
| `archive-comments-user` | `(email)=(commenting@user.s)` — both victims |
| `archive-users-user`, `archive-groups-user` | `(email)=(newuser@new.n)` |
| `group-agroup` | `(label, type_string)=(agroup, core)` |
| `group-test-args-group` | `(test_args_group, core)` |
| `group-test-metadata-group` | `(test_metadata_group, core)` |
| `group-test-dump-group` | `(test_dump_group, core)` |

`NameError` appears nowhere in 3410 lines, which is what clears the anchored `reset_storage()`
inverse — reverting the wrong one of that file's four occurrences would have gone red for a reason
that proves nothing.

Both victims of `archive-comments-user` fail, which was not predicted: both guards on that file are
load-bearing, neither redundant.

## Follow-ups

- **A `just eval` recipe.** The four-line preamble that resolves flake.lock's nixpkgs to a store
  path and evaluates one expression against a chroot store was retyped **24 times** this session.
  `just check-no-daemon` runs the whole suite and is the wrong granularity for "what is this
  attribute's drvPath". `scripts/no-daemon-check.sh` already has `locked_nixpkgs` to extract into
  `scripts/nix-eval.sh` behind a one-line recipe. Not done in this session — left as the next
  obvious cleanup.
- **`prek` needs `XDG_CACHE_HOME` in the sandbox.** `prek run --files` fails with
  `failed to create directory /home/eric/.cache/prek: Read-only file system` unless
  `XDG_CACHE_HOME` is pointed at `$TMPDIR`. Used 24 times. Belongs in the hooks recipe or in
  `.claude/settings.local.json`.
- Added: four `aiida-*` recipes in the `Justfile`.
- **Next session — resolve the `origin/main` divergence first.** `origin/main` is at `97bff2a`
  ("Update nixpkgs-qchem digest to 6cd7314", #17). Relative to this branch it is +30/-325 lines
  across `flake.nix` and `flake.lock`, so the conflict is this branch's flake additions against
  that digest bump. Do that on its own before anything else lands. Never hand-edit `flake.lock` —
  `nix flake update nixpkgs-qchem`.
- **Session after that — the new packages.** Fifteen clones are already under `wc/aiida/`:
  `aiida-ase`, `aiida-firecrest`, `aiida-gromacs`, `aiida-lammps`, `aiida-nwchem`, `aiida-phonopy`,
  `aiida-pythonjob`, `aiida-restapi`, `aiida-shell`, `aiida-submission-controller`,
  `aiida-wannier90`, `aiida-wannier90-workflows`, `aiida-workgraph`, `aiida_siesta_plugin`, plus
  `node-graph` and `node-graph-widget` for workgraph. Order by leverage: `aiida-shell` first — aiida-core's own docs
  name it more than any other plugin, its footprint is essentially aiida-core alone, and it turns
  the ~60 programs already reachable through `pkgs.qchem.*` into things AiiDA can drive without a
  plugin each. Expect the sdist-has-no-tests trap on every one of these; see `AGENTS.md`.
- Triaged: the `globals` scan first reported **24** candidates and every one was safe. Four blind
  spots caused it, each fixed in the script: a `reset_storage()` before the assertion; a query
  against an opened *archive* rather than the profile (`archive.querybuilder()`); an append
  constrained through a relationship (`with_node=`, `with_group=`) rather than `filters=`; and a
  builder that is populated but never run — AiiDA's graph explorer takes one as a traversal
  template seeded from an explicit basket of pks, which is all seven `test_age.py` entries. The
  scan now reports **2**, and both compare two counts of the same table against each other, so a
  leftover row moves both sides equally. Nothing to act on. Verified the precision cost no
  sensitivity: run against *unpatched* source it still flags every victim this repo fixed.
- The literal scan reads `tests/` only, not `src/aiida/tools/pytest_fixtures/`. `aiida_localhost`
  creates `Computer(label='localhost')` there, and two archives carry a `localhost` computer; the
  import machinery renames on conflict (`localhost_1` appears in the fixtures), so this looks
  handled — but the scan cannot see it either way.
- The nine `log*` files and `0.txt` at the repo root are untracked build output from this session
  and can be deleted.
- `tests/aiida/ordering.nix` is not reachable from `nix-build tests -A all` by design. If that is
  ever revisited, note that each entry builds a full aiida-core variant.
