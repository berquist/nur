---
date: 2026-09-07
slug: quacc-defects-cluster
status: done
sessions: ["5395dda5-05ab-45e6-aaa8-d8f55fb49a42"]
touches:
  - "pkgs/enumlib/**"
  - "pkgs/vise/**"
  - "pkgs/tensorpotential/**"
  - "pkgs/trainstation/**"
  - "pkgs/hiphive/**"
  - "pkgs/cmcrameri/**"
  - "pkgs/matplotlib-label-lines/**"
  - "pkgs/pydefect/**"
  - "pkgs/doped/**"
  - "pkgs/shakenbreak/**"
  - "pkgs/maml/**"
  - "pkgs/matcalc/**"
  - "pkgs/quacc/**"
  - "pkgs/atomate2/**"
  - "overlays/default.nix"
  - "default.nix"
  - "ci.nix"
  - "docs/TODO.md"
  - "AGENTS.md"
---

# The quacc[defects] cluster, and three bugs only a real build could find

Ten new packages, eight commits, and the end of the materials chain that started
on 2026-08-30.  Two of the ten are not Python: `enumlib` is Fortran, and
`tensorpotential` is the first unfree package this repo has ever carried.

The theme, if there is one: **eval cannot find any of this.**  Every interesting
defect here — a console script that could not start, a test suite that parallel
workers wrecked, a shipped shell script with no interpreter — survived a clean
`just check-no-daemon` and showed up only when the user ran the build.

## Ask

Verbatim and in order.  No plan mode.  The session was driven prompt by prompt:
the user ran every `nix build` in a separate terminal, redirected it to a
`log-<name>` file in the repo, and asked for it to be read.

> keep going with what you were doing before

> when you're done read "log-nix-build"

> read "log-maml" and "log-enumlib"

> Why only rewrite to /bin/sh and not properly depend on the shell as a Nix package input?

> read "log-enumlib"

> add a todo for figuring out what the actual patch for compare_enum_files.x is

> ok, keep going with whatever's next

> 1. read "log-vise"  2. package grace-tensorpotential  3. i've cloned those three repos

> read "log-vise"

> Sorry but this explanation of the potcar stuff for vise is completely cryptic.  If the tests require running VASP and the problem is that we don't have VASP, just say so.  If there is test data then reword things in plain English.

> ok keep going

> keep going with pydefect

> read "log-pydefect"

> keep going with doped

> read "log-doped"

> read "log-doped"

> read "log-doped" again

> keep going with shakenbreak

> read "log-shakenbreak"

> read "log-shakenbreak"

> read "log-shakenbreak"

> read "log-shakenbreak"

> keep going

> yes, write the worklog

The session opened with a `/clear`, so "keep going with what you were doing
before" had to be answered from the previous session's transcript
(`c5ac632d-41cb-4586-949a-18f6454e9094.jsonl`) rather than from context.
`enumlib` was in flight at the handoff; everything from `vise` on is new here.

## Plan

There was none in the plan-mode sense.  The standing plan is the "Deferred
packaging" table in `AGENTS.md`, which names each missing package, what wants it,
and what blocks it; each prompt took the next row.  The order the dependency
graph forced:

    vise → pydefect ┐
    trainstation → hiphive ┤
    cmcrameri, matplotlib-label-lines ┤
                                      └→ doped → shakenbreak → quacc[defects]

with `enumlib` (for atomate2's `test_magnetic_orderings`) and `tensorpotential`
(for `matcalc[grace]`) as two unrelated errands taken on the way past.

## Out-of-band

The user ran every build themselves — the sandbox blocks `socket(AF_UNIX)`, so
nothing here can reach the nix-daemon.  None of it went through `!` in the
prompt, so the commands are not in the transcript; only their output survives, as
files still in the working tree:

| Log | What it settled |
|---|---|
| `log-nix-build`, `log-enumlib` | `/bin/bash` missing; then the version-stamp ordering |
| `log-maml` | `PermissionError: '/homeless-shelter'` from matgl's `config.py` |
| `log-vise` | 281 passed / 10 failed / 57 errors → 326 / 9 / 16 |
| `log-pydefect` | 294 passed / 1 failed / 69 errors, all 69 the same missing fixture |
| `log-defects` | pydefect again, after the fix: **363 passed, 1 skipped** |
| `log-doped` | 108 / 148 / 128 → **99 passed, 8 skipped, 41 deselected in 712 s** |
| `log-shakenbreak` | five rounds, ending **141 passed, 1 deselected in 268 s** |

Worth doing differently next time: running these through `!` in the prompt would
put the command *and* its output in the transcript, which is what makes a session
reconstructable.  As it is, the exact `nix build` invocations are lost and only
the redirected output remains.

## Changes

Eight commits, oldest first.

| Commit | What |
|---|---|
| `71513c1` | `enumlib`, and atomate2's `test_magnetic_orderings` unblocked |
| `a360034` | `maml` import check given a writable `HOME` |
| `9577e20` | `vise` |
| `55d4916` | `tensorpotential`, and `matcalc`'s `grace` extra |
| `2fbda14` | `trainstation`, `hiphive`, `cmcrameri`, `matplotlib-label-lines` |
| `8521913` | `pydefect` |
| `502cc8d` | `doped`, cutting the shakenbreak cycle |
| `b9667c9` | `shakenbreak`, and `quacc`'s `defects` extra |

Three of the ten are re-exported as top-level attributes — `enumlib`, `vise`,
`shakenbreak` — and seven stay internal, reachable only through
`python313Packages`, because each has exactly one dependant.  `tensorpotential`
is internal for a different reason; see below.

`docs/TODO.md` gained one entry, and `AGENTS.md` gained a row per package in the
"Deferred packaging" table plus fifteen rows in the "Where the explanations live"
index.

## Outcome

### The shell is a dependency, not a path

`enumlib`'s `src/Makefile` sets `SHELL = /bin/bash`, and the build sandbox has
only `/bin/sh`, so `make` died with `Error 127`.  The first fix rewrote it to
`/bin/sh`, and the user rejected that:

> Why only rewrite to /bin/sh and not properly depend on the shell as a Nix
> package input?

Right, and the corrected form is `${stdenv.shell}` — a store path, and no new
input needed, since stdenv already closes over its own shell.  `/bin/sh` inside
the sandbox is an accident of the sandbox; it is not there on the host and it is
not a dependency anything declares.

The same `/bin/bash` problem then turned up in `shakenbreak`, and the answer
there is the *other* spelling.  The rule that came out of the pair, now recorded
at both sites:

- **`stdenv.shell`** for a script read only at build time (enumlib's Makefile).
- **`runtimeShell`** for a script that is installed and runs on the user's
  machine (shakenbreak's `SnB_run.sh`).

### `compare_two_enum_files.x` is broken upstream, and the fix is determined

The target would not compile.  Two separate upstream defects, both traced to the
commit that introduced them:

- **557db14** (2019-09-10) commented out four format continuation lines, leaving
  a trailing `&` pointing at nothing.
- **f6694db** (2021-08-16) dropped `LatDim` from `get_dvector_permutations`'s
  argument list at the definition but not at this call site.

The target is dropped from `buildPhase` and the diagnosis is in `docs/TODO.md`.
One correction worth recording, because it was made in the comment and then had
to be unmade: an earlier draft said fixing it "would mean guessing which argument
upstream meant to drop".  It would not — the signature change is unambiguous, and
what actually remains is *verification* against `support/comparetests.py`, not
diagnosis.

### A phony rule and the order of `make` targets

`enumlib` stamps a `git describe` string into the binary through a phony
`pre_comp` target that runs `sed` over a source file.  Naming `libenum.a` first
— as upstream's travis config does — compiles the objects *before* `pre_comp`
runs, so the stamp lands in a file nothing recompiles.  Reordered so `enum.x`
comes first, and `libenum.a` dropped from the target list entirely.

### `boltztrap2` is a runtime dependency of vise, and `pythonImportsCheck` said otherwise

The first `vise` derivation had `boltztrap2` in `nativeCheckInputs`, checked
`vise.cli.main`, and passed its import check — while four test modules failed to
collect.  `vise/util/phonopy/phonopy_input.py` imports boltztrap2 at module
scope and `vise/cli/main_util.py` imports through it, so the `vise_util` console
script would not have started for a user.

**The lesson is about `pythonImportsCheck`, not about boltztrap2:** check the
modules the console scripts actually reach, not just the package root.  The check
now names `vise.cli.main_util` and `vise.util.phonopy.phonopy_input` for exactly
that reason.

### Rejected: setting `PMG_VASP_PSP_DIR` for vise

Twenty-three vise tests want VASP's licensed POTCAR files.  An early attempt
pointed `PMG_VASP_PSP_DIR` at upstream's own test directory in `preCheck`.  **It
changed nothing** — the identical 23 tests failed with it and without it — so the
`preCheck` was removed rather than left in place looking load-bearing.

Do not retry this.  Upstream gutted the stand-in POTCARs in a later commit, and
current pymatgen validates what it reads and rejects them, so there is nothing
for the variable to point at.  Configuration that moves an error without fixing a
test is worse than no configuration.

The user's other correction landed here too:

> Sorry but this explanation of the potcar stuff for vise is completely cryptic.
> If the tests require running VASP and the problem is that we don't have VASP,
> just say so.

It was cryptic because it had been written as a traceback rather than an
explanation.  The rewrite leads with the four plain facts in order: these tests
never run VASP; they need VASP's licensed POTCAR files, which are not
redistributable; upstream's stand-ins were gutted; pymatgen now validates them
and rejects them.  A contradictory leftover note in `enabledTestPaths` was fixed
in the same pass.

### The unfree one

`tensorpotential` (GRACE) ships an Academic Software Licence — GPLv2 with a
non-commercial clause, and "not an open-source licence" by its own preamble.  Two
things follow:

1. **It must not be a top-level attribute.**  `just ci-eval` runs
   `nix-env -f . -qa '*' --meta --xml --drv-path`, and an unfree top-level
   attribute is an *evaluation throw*, not a skip — it would take the whole eval
   pass down rather than being filtered.  It is reachable as
   `python313Packages.tensorpotential` only.  This is also, incidentally, the
   answer to the question `ci.nix` has carried since the template: the unfree
   filter looked inert and is not.
2. **`free` and `redistributable` are spelled out** in the licence attrset.  A
   raw attrset gets none of `mkLicense`'s defaulting, so omitting them does not
   mean "false", it means absent.

Verified that taking the extra costs `matcalc` nothing: no `tensorpotential`
appears in its propagated, native or plain build inputs.  The same check was run
for `quacc[defects]`, which takes only `tblite` into its own `nativeCheckInputs`.

### 69 errors, one missing plugin

`pydefect`'s first build reported 69 errors and 1 failure.  All sixty-nine were
the same absent `mocker` fixture — pytest-mock, the identical omission vise's
first build had turned up an hour earlier.  Without the plugin these are
*collection* errors rather than failures, which is why the count looks alarming
and the cause is one line.

The follow-up run (`log-defects`) came back **363 passed, 1 skipped**.  Note that
commit `8521913`'s message says "not re-run since; the sandbox has no
nix-daemon" — accurate when written, stale a minute later.  The green run is the
record.

### doped's suite is hostile to pytest-xdist

108 passed / 148 failed / 128 errors on the first run.  Not 148 separate bugs:
`setUpClass` does `shutil.move` on `examples/CdTe/v_Cd_example_data/*`, so
parallel workers move each other's fixtures out from under themselves.  Dropping
`pytest-xdist` took it to 100 passed / 17 failed / **0 errors**, and the
remaining 17 were ordinary deselections.

This is the third package in this repo with the same shape, after `fireworks` and
now `shakenbreak`, and it costs real time — doped's check phase runs 712 seconds
serially.  The note is at `nativeCheckInputs` in all three, because the failure
mode when someone re-adds xdist is a wall of unrelated-looking errors, not a
timeout.

### `disabledTests` is a substring match

`disabledTests = [ "test_DefectsParser_CdTe" ]` also deselected
`test_DefectsParser_CdTe_unrecognised_subfolder`, which passes.  `-k` is a
substring match, so any name that is a prefix of another silently takes the other
with it.  Moved to an exact node id:

    pytestFlags = [
      "--deselect=tests/test_analysis.py::DefectsParsingTestCase::test_DefectsParser_CdTe"
    ];

One entry out of forty needed this.  The other 39 have no prefix collision, and
checking for one is now part of adding a `disabledTests` entry.

### The doped ↔ shakenbreak cycle, cut permanently

Each declares the other.  Nix cannot express that, so one side has to give.  The
cut was decided by counting, not by convenience:

- `shakenbreak` imports `doped` **at module scope in five modules** — `cli`,
  `plotting`, `analysis`, `input`, `energy_lowering_distortions`.  There is no
  shakenbreak without doped.
- `doped`'s eight `import shakenbreak` statements are **all function-local**.

So `doped` carries `pythonRemoveDeps = [ "shakenbreak" ]` and shakenbreak
declares doped.  **This is permanent, not a bootstrap step** — adding it back
after both exist would reintroduce the cycle.

One claim had to be withdrawn along the way: "nothing is lost" by dropping it is
not quite true.  `doped/utils/parsing.py` imports shakenbreak unguarded for dimer
detection, so that one path raises for a user who installs doped alone.  A user
who installs `shakenbreak` — which is the re-exported, user-facing half — gets
both and never sees it.

### shakenbreak took five builds, and found a bug that would have shipped

Each round found the layer under the last:

1. **140 passed / 2 failed.**  `test_run` could not find `snb-run`: it shells out
   to the console script by name.  `preCheck` puts `$out/bin` on PATH — the same
   one-line fix `aiida-pseudo` and `aiida-gromacs` already carry.
2. **Same counts, different reason.**  `snb-run` is not an entry point that does
   the work; it hands off to a shell script shipped inside the package,
   `subprocess.call(f"{os.path.dirname(__file__)}/SnB_run.sh ...", shell=True)`,
   and that script opens `#!/bin/bash`.  Nothing provides `/bin/bash` — not the
   sandbox, and **not NixOS**.  So the script never executed, `snb-run` produced
   no output at all, and the only sign was an assertion against an empty string.
   This is a real defect for anyone running it on NixOS, not a test artefact.
   `postPatch` rewrites the shebang to `runtimeShell`.
3. **140 / 1, with the script now running.**  It reaches for `bc` seven times to
   compare energies.  `bc` is in neither stdenv nor a normal user environment.
   Wrapped rather than left to the user **because the failure is silent**: with no
   `bc` the command substitution yields an empty string, the arithmetic test
   around it is false, the branch is skipped, nothing is printed, and `snb-run`
   reports success having quietly declined to filter the distortions stuck in
   high-energy basins.  The test catches it only because it asserts on the message
   that branch would have emitted.
4. **A fixup-phase abort**, and this one was mine:
   `Builder called die: makeWrapper doesn't understand the arg --prefix PATH : /nix/store/…`.
   Under `__structuredAttrs = true`, each element of `makeWrapperArgs` is **one
   argv entry**, so a whole flag written as a single string arrives as a single
   argument.  `pkgs/dotdrop` already had the correct four-element form and it had
   not been followed.
5. **141 passed, 1 deselected, 268 s.**  Green, `test_run` included.

The one deselection is `test_compare_struct_to_distortions`, which is pandas 3
moving underneath: `energy_lowering_distortions.py` keeps floats and strings in
one column and sorts with `key=abs`, pandas 3 stores that column Arrow-backed, and
`abs` reaches pyarrow rather than numpy.  Left to upstream rather than patched —
their own comment twenty lines on says the code "needs to be done this way", so
the dtype handling is theirs to reconsider.

### Smaller findings

- **`matplotlib-label-lines`** needs `enabledTestPaths = [ "labellines/test.py" ]`.
  Its one test module is named `test.py`, which pytest's default `python_files`
  matches neither as `test_*.py` nor as `*_test.py`.  This is the `pgtest` trap,
  now hit twice; the sdist-has-no-tests section of `AGENTS.md` already warns
  about it.
- **`maml`** failed its *import* check on `/homeless-shelter`: matgl's
  `config.py` creates `~/.cache/matgl` at import time.  `HOME` set in `preBuild`,
  not `preCheck`, because the import check runs before the check phase.
- **`cmcrameri`** needs `env.SETUPTOOLS_SCM_PRETEND_VERSION` — nothing errors
  without it, the version simply comes out as `0.0.0`.
- **`hiphive`** and **`trainstation`** are on GitLab, so `fetchFromGitLab`.
  hiPhive's `tests/integration` fits real force-constant models and takes minutes
  per file; only `tests/unittests` runs.

## Follow-ups

- **`just ci-matrix` has not been run with the cluster in it.**  `shakenbreak`
  is re-exported, so `ci.nix` now builds it and doped with it on every leg: an
  873 MB fetch and a ~12-minute serial check phase, three times.  Making
  shakenbreak internal is a two-line change (drop it from `default.nix`'s
  `inherit (py)` and from the top-level `inherit` in `overlays/default.nix`) and
  it would stay reachable as `python313Packages.shakenbreak`.  Flagged to the
  user; not decided.
- **`docs/TODO.md`: repair `compare_enum_files.x` and send the patch upstream.**
  Both defects are diagnosed with commit provenance; what remains is verifying
  the fix against `support/comparetests.py`.
- **Commit `8521913`'s verification paragraph is stale** — it says pydefect was
  not re-run, and `log-defects` shows it green at 363 passed.  Three commits back,
  so not worth a rebase; recorded here instead.
- **Sessions between 2026-08-30 and this one have no worklog.**  Commits
  `5c7a3a1..1c711b3` — `emmet-core`, `atomate2`, `matcalc`, `quacc`, `sevenn`,
  `mp-api`, `maml` — are the gap.
- **The deferred-packaging list now holds only genuinely blocked entries**:
  `torch-sim` / `orb-models` / `mattersim` / `pet-mad` (all walled behind NVIDIA's
  `nvalchemi-toolkit-ops`), `deepmd-kit`, `fairchem`, the conda-first `openff-*`
  family, `RMG-Py`, `PsiDataViz`, `crest`.  Nothing there is one packaging session
  away.
- **Proposed recipe — `just eval '<expr>'`.**  The five-line incantation that
  sets `XDG_CACHE_HOME`, clears `NIXPKGS_CONFIG`, resolves `NIX_PATH` from
  `flake.lock`'s narHash and runs
  `nix-instantiate --eval --strict --store dummy://` was retyped twelve times this
  session.  `scripts/no-daemon-check.sh` encapsulates it for the whole suite and
  the `no-daemon-check` skill documents it, but there is nothing for a one-off
  question like "what does `shakenbreak.makeWrapperArgs` evaluate to".  It belongs
  in `scripts/sandbox-eval.sh` behind a one-line recipe, per the "a recipe that
  grows past a few lines" rule.  Not written — proposing, not doing.
