---
date: 2026-09-19
slug: drop-python313-pin
status: done
sessions: ["f345a633-229e-4aec-b7e0-f3c9d9f22c4d"]
touches:
  - "default.nix"
  - "overlay.nix"
  - "ci.nix"
  - "flake.nix"
  - "overlays/**"
  - "pkgs/qcportal/**"
  - "pkgs/qcfractal/**"
  - "pkgs/qcfractalcompute/**"
  - "pkgs/qcarchivetesting/**"
  - "pkgs/aiida-psi4/**"
  - "scripts/channel-gaps.nix"
  - "scripts/update-universe.nix"
  - "tests/**"
  - "docs/TODO.md"
---

# Drop the python313 pin and follow the channel default

## Ask

> Now that Python 3.14 is no longer blocked by the QCArchive packages, I want to remove the
> restriction on Python 3.13.

Then, mid-turn, while the exploration agent was still running:

> Tell me what you want me to get from GitHub

And after the change was staged:

> 26.05 is 3.13.15.  yes, write the worklog.

Three decisions were taken through `AskUserQuestion` before the plan was written, each with the
recommended option chosen:

- **Attribute name** — rename the exposed set to `python3Packages`, rather than keeping the
  `python313Packages` spelling or carrying both for a deprecation period.
- **`aiida-psi4`** — mark it `broken = pythonAtLeast "3.14"`, rather than porting it to
  `qcelemental.models.v2` in this change or leaving the failure for CI to find.
- **Verification depth** — evaluation now, builds as a follow-up session.

## Plan

# Drop the Python 3.13 pin and follow the channel default

## Context

`default.nix:31` binds `py = pkgs'.python313Packages` instead of following the channel's
default interpreter. The pin exists for one reason, written out at `pkgs/qcportal/default.nix`'s
`meta`: qcportal 0.65 was pydantic v1 throughout, and `qcelemental`'s v1 models become
placeholder classes on Python 3.14, so `index: Array[str]` died with
`TypeError: type 'Array' is not subscriptable`.

**That blocker is gone.** All four QCArchive packages are already at **0.70**, which asks for
`pydantic>=2.11`, declares `requires-python = ">=3.10"` with no upper bound, contains no
`Array[` anywhere, and reaches `qcelemental.models._v1v2` rather than the v1 shim (verified
against `wc/QCFractal`, tag `v0.70-2-ga7a85a4d4`). Only the `broken = pythonAtLeast "3.14"`
markings and the pin itself are left behind.

Two things measured from the sandbox before planning, both of which change the shape of the job:

1. **Evaluation on 3.14 is already clean.** Every directory under `pkgs/` was probed against
   `python314Packages` with all overlays composed. 121 attributes force `drvPath` without
   complaint. The only non-`ok` results are the four QCArchive gates, `aiida-gaussian` (cclib,
   broken by design), `tensorpotential` (unfree), and names that are top-level or
   `python3.pkgs` attributes rather than members of a Python set. The TODO's "measure the 137
   ungated packages" step is therefore **done, and the answer is that nothing fails to
   evaluate**. Builds are a separate question.
2. **The pinned `nixpkgs-qchem` is 26.11pre-git with `python3 = 3.14.7` and a `python314`
   attribute.** So `flake.nix`'s interpreter override in `qchemPkgs` becomes a no-op, and Psi4
   and its Python closure go back onto `nix-qchem.cachix.org` instead of building from source.
   This is the payoff `README.md:161-167` and `flake.nix:211-216` both predicted.

One blocker the TODO does **not** list was found: `aiida-psi4`. Its
`aiida_psi4/data/__init__.py` does `from qcelemental import models` and
`schema = models.AtomicInput`; on 3.14 that name is a v1 placeholder whose `__init__` raises
`RuntimeError`. It evaluates fine and fails in the check phase. Per decision, it gets the
marking the QCArchive four are losing, and the port becomes a TODO item.

Goal: **follow** the channel default (`py = pkgs'.python3Packages`), not *support* both sets.
The exposed attribute is renamed to `python3Packages` to match.

## The change

### 1. Unblock QCArchive — `pkgs/{qcportal,qcfractal,qcfractalcompute,qcarchivetesting}`

- Delete `broken = pythonAtLeast "3.14";` and the now-unused `pythonAtLeast` argument from all
  four. Deadnix will flag a left-behind argument.
- `pkgs/qcportal/default.nix`: the comment at `meta` (lines 61-74) describes 0.65 and is now
  wrong in every particular. Replace it with nothing — there is no gate left to explain. Keep
  a short note only if it says why the package *no longer* needs one.
- `pkgs/qcportal/default.nix`: **the 0.70 dependency delta was never applied.** Upstream's
  `pyproject.toml` asks for `packaging` and `python-dateutil`, and no longer for `dateutils` or
  `pytz`. The derivation still declares `dateutils` and `pytz`, which are the wrong packages —
  `dateutils` is a distinct distribution from `python-dateutil`, and both exist in nixpkgs.
  Imports work today only because pandas drags the right ones in transitively.
- `pkgs/qcfractal`, `pkgs/qcfractalcompute`, `pkgs/qcarchivetesting`: dependency lists already
  match upstream 0.70; only the gate and its argument go.

### 2. Move the pin — `default.nix`

- `py = pkgs'.python3Packages;`, and rewrite the rationale block above it (lines 21-30) to
  record that the repo follows the channel default and what that means per channel.
- Rename the exposed attribute: `python3Packages = pkgs'.lib.dontRecurseIntoAttrs py;`. Keep
  `dontRecurseIntoAttrs` and every word of the reasoning at lines 48-59 — none of it was about
  the version.
- The `inherit (pkgs') dotdrop harmonwig moltui;` note (62-73) says these are "built against the
  default python3, not the 3.13 pin below". That distinction dissolves; reword rather than
  delete, since `harmonwig` and `moltui` are top-level for reasons unrelated to the interpreter.
- `internalPackages` is unchanged in content — still `chemfiles` and `trexio` — but its note
  names `python313Packages.<name>` five times.

### 3. The five overlay alias lists — `overlays/default.nix`

`inherit (final.python313Packages)` → `inherit (final.python3Packages)` at the top-level alias
blocks of the `cheminformatics` (~340), `chemtools` (~474), `materials` (~932), `aiida` (~1376)
and `qcfractal` (~1499) overlays.

Two comments carry real reasoning that has to be revised rather than search-replaced:

- **`aiida` (1363-1368)** claims following the default `python3` "is not an option for this
  family either", citing `aiida-psi4`'s qcelemental v1 import. That is now the *only* package it
  is true of, and it is handled at the derivation instead. Rewrite.
- **`qcfractal` (1486-1498)** says "python313 rather than python3: qcportal does not import on
  3.14". Gone.

**Do not touch the cclib spellings.** `final.python3.pkgs` at lines 162, 370-392 stays exactly
as it is, and the warning at 154-160 — that `final.python3Packages` is an alias to the
*versioned* set while cclib's overlay rebuilds `python3` — stays true and becomes *more*
dangerous, because the repo now uses `final.python3Packages` for everything else and the two
spellings sit one letter apart. Strengthen that note; do not weaken it.
`tests/cheminformatics/default.nix:198-222` is what catches a slip here.

### 4. The reserved-key predicate, in four places

`"python313Packages"` → `"python3Packages"` in `overlay.nix:28`, `ci.nix:42`,
`scripts/channel-gaps.nix:52` and `scripts/update-universe.nix:70`. `AGENTS.md` already records
that adding a reserved key means editing all of them; renaming one is the same edit.

`scripts/channel-gaps.nix:63-64` also builds `python313Packages.${name}` probe targets, and
`scripts/update-universe.nix:88-92` hardcodes five `python313Packages.*` extras
(`monty`, `pycifrw`, `qcelemental`, `qcengine`, `tensorpotential`). **These move together with
the attribute or the updater silently stops covering those five** — `update-universe.nix`'s
`missing` check aborts rather than warns, which is the safety net.

### 5. Flake, tests, modules

- `flake.nix:363, 374, 400` — three `pkgs'.python313Packages.*.override` sites
  (`fairchem-data-oc`, `atomate2`, `parmed`).
- `flake.nix:194, 201` — `workerPython` and `qchemPythonAttr` are **derived** and need no edit;
  they will resolve to `python314`. The commentary at 211-216 about the override costing a cache
  miss should be updated to say the override is now a no-op on the locked input.
- VM tests: `pkgs.python313.withPackages` → `pkgs.python3.withPackages` at
  `tests/qcarchive/vm.nix:644, 707`, `tests/aiida/vm.nix:497`, `tests/materials/vm.nix:41`.
  The comment at `tests/qcarchive/vm.nix:639-643` explains that `pkgs.python3` "refuses to
  evaluate here" — delete it, that was the gate.
- `tests/aiida/vm.nix:370, 380, 518`, `tests/aiida/isolation.nix:64`,
  `tests/aiida/ordering.nix:88`, `tests/aiida/pollution-scan.nix:28` — plain attribute renames.
- The four `*-python-pin` tests and the `*-toplevel-packages` / internal-dependency tests in
  `tests/{qcarchive,aiida,cheminformatics,chemtools}/default.nix` — rename the spellings; the
  assertions themselves are unchanged and are what prove `default.nix` and `overlays/` still
  agree.
- Two assertions that must keep passing and were checked: `basePkgs.python3Packages.pymatgen`
  still throws on 3.14 (nixpkgs' `disabled = pythonAtLeast "3.13"` covers it), and
  `otherPython = pkgs.python312` in `tests/qcarchive/default.nix:57` still differs from the
  default.
- `nixos-modules/aiida.nix:364` — the `literalExpression` example. Both modules derive their
  interpreter from `cfg.package.pythonModule` and need no other change.

### 6. `aiida-psi4`

Add `broken = pythonAtLeast "3.14";` to `pkgs/aiida-psi4/default.nix` with a note giving the
actual mechanism: `models.AtomicInput` is a v1 placeholder on 3.14 and
`AtomicInput.validate()` instantiates it, so this fails in the check phase rather than at
import. Point at `qcelemental/models/v1/__init__.py`'s `_make_placeholder`. Nothing here
depends on `aiida-psi4`, so no other package needs re-marking.

### 7. Documentation

- `Justfile` — delete the `repro-gh` recipe and its comment (310-326). It exists only to
  reproduce the failure being removed.
- `docs/TODO.md` — close "Allow Python 3.14" (56-110); the separate item at ~499 about moving
  the pin "to whatever `nixpkgs-qchem` calls `python3`" resolves with it and should say so and
  note the recovered Psi4 cache hit. Add a new item for the `aiida-psi4` port to
  `qcelemental.models.v2`, recording that the recorded `mock-psi4` fixture digests and the
  `pydantic.v1.error_wrappers` patch move with it.
- `AGENTS.md` (`CLAUDE.md` is the symlink) — the "three edits" section (611-637), the cclib-trap
  note (127-130), the `internalPackages` / reserved-key notes, the "shares the `python313` pin"
  and "default `python3` rather than the 3.13 pin" lines, and the index row
  "Why `python313` and not `python3`?", which should now point at the *absence* of a pin.
- `README.md:36, 69, 151-155, 161-167` — the attribute spellings and the paragraph claiming the
  QCArchive and AiiDA families are pinned to 3.13.
- `scripts/no-daemon-check.sh:143`, `scripts/locked-nixpkgs.sh:20-25`,
  `scripts/update-packages.sh:48-49`, `scripts/fetch-build-logs.sh`, `scripts/demux-build-log.sh`
  — comments naming the pin or `python3.13-` derivation prefixes. Cosmetic, but
  `locked-nixpkgs.sh`'s worked example is exactly this situation and should be re-aimed rather
  than deleted.

## Ordering

Do §1 and §6 first and evaluate. With the gates gone but the pin still in place the tree is
consistent, and `just eval` will answer whether the QCArchive four still resolve on 3.13.
Then §2-§5 as one sweep, because the `*-python-pin` tests fail on any partial rename — that is
what they are for. §7 last.

`rg -n 'python313' --glob '!wc/**'` reaching zero hits outside `.claude/worklog/` is the
completeness check.

## Verification

Per decision: evaluation now, builds as a follow-up session.

```sh
just fmt && just lint                 # nixfmt, statix, deadnix (the dropped arguments)
just check-no-daemon                  # both eval suites + VM instantiation, no daemon
just eval qcportal.version            # and python3Packages.qcportal, aiida-psi4.meta.broken
just ci-eval                          # nix-env -qa --meta --drv-path over everything
just channel-gaps                     # all three channels, one attribute per process
just check                            # eval suites, VM tests, prek hooks — needs a daemon
prek run --files <changed>
```

`just check-no-daemon` prints `<nixpkgs> default python3 = …` after the first suite; it must
read 3.14.7 for the locked input, or the run is not checking what CI checks
(`scripts/locked-nixpkgs.sh`).

Worth confirming before the build session: the default `python3` on all three CI channels
(`nixpkgs-unstable`, `nixos-unstable`, `nixos-26.05`). The locked one is 3.14.7; the other two
need the network. If `nixos-26.05` is still 3.13, that leg simply does not move.

**Follow-up session, explicitly out of scope here:** `just ci-matrix` with `--keep-going`, then
`just build-logs` on the result. 121 packages have never been *built* on 3.14, and the
sdist-has-no-tests experience in `AGENTS.md` says to budget for several rounds where each fixed
failure reveals the next.

## Not doing

- Supporting 3.13 and 3.14 side by side (`python314Packages` beside `python313Packages`, and a
  second copy of every list in the "three edits" section). The TODO raises it as the other
  reading of "allow"; following the default was chosen.
- Porting `aiida-psi4` to `qcelemental.models.v2`. Recorded as a TODO item instead.
- Any `pythonRelaxDeps` / test-selection churn that a 3.14 build turns up.

## Out-of-band

Nothing was run with `!` this session. One fact came from the user by hand, and it is the one
thing the sandbox genuinely could not reach:

> 26.05 is 3.13.15.

The channel tarballs need the network, so only the *locked* nixpkgs (3.14.7) was verifiable
here. That answer is load-bearing enough that it went into `default.nix`'s comment and
`docs/TODO.md` rather than just being noted: it is what makes the CI matrix span two
interpreters rather than one.

Nothing was needed from GitHub. That question was asked mid-turn and the answer was "nothing",
which is worth recording because three separate things looked like they would need it and did
not:

- `wc/QCFractal` was already at `v0.70-2-ga7a85a4d4`, so the real 0.70 `pyproject.toml` for all
  four distributions was on disk.
- `nixpkgs-qchem` was already in the store. A flake input is a fixed-output path, so its
  location is a pure function of the narHash in `flake.lock` — the trick
  `scripts/locked-nixpkgs.sh` uses for `nixpkgs` works for **any** input:
  `nix-hash --to-base16` on the narHash, then `nix-store --print-fixed-path --recursive sha256
  <hash> source`. All three of `nixpkgs-qchem`, `nixos-qchem` and `cclib` resolved.
- qcelemental's 3.14 placeholder mechanism was read out of the *installed* store path
  (`/nix/store/…-python3.13-qcelemental-0.50.4/lib/python3.13/site-packages/qcelemental/`)
  rather than a clone.

`builtins.getFlake` on a GitHub URL was tried first and was denied by the proxy, which is what
prompted looking for the store path instead. It is the better move anyway: it resolves the
revision the lock actually names, with no network.

## Changes

39 files, staged, one commit drafted at `.git/drop-python313-pin-commit-msg.txt`.

**The gates (§1, §6).**

- `pkgs/{qcportal,qcfractal,qcfractalcompute,qcarchivetesting}/default.nix` — the four
  `broken = pythonAtLeast "3.14"` lines and their `pythonAtLeast` arguments removed.
- `pkgs/qcportal/default.nix` — also the 0.70 dependency delta, which the updater had never
  applied: `dateutils` + `pytz` out, `python-dateutil` + `packaging` in.
- `pkgs/aiida-psi4/default.nix` — gains the marking the four lost, with the mechanism written
  out at `meta`.

**The pin (§2-§5).**

- `default.nix` — `py = pkgs'.python3Packages`, exposed attribute renamed, and the rationale
  block rewritten to say what following the default costs per leg.
- `overlays/default.nix` — the five `inherit (final.python3Packages)` lists, the two
  pin-justifying comments rewritten, and the cclib and openimageio notes strengthened rather
  than merely renamed.
- `overlay.nix`, `ci.nix`, `scripts/channel-gaps.nix`, `scripts/update-universe.nix` — the four
  copies of the reserved-key predicate, plus channel-gaps' probe targets and update-universe's
  five hardcoded extras.
- `flake.nix` — three `.override` sites; `workerPython` and `qchemPythonAttr` needed no edit,
  being derived.
- `tests/{qcarchive,aiida,cheminformatics,chemtools}/default.nix`, `tests/aiida/{vm,isolation,
  ordering,pollution-scan}.nix`, `tests/{qcarchive,materials}/vm.nix` — attribute renames, plus
  `pkgs.python313.withPackages` → `pkgs.python3.withPackages` in four VM tests.
- `nixos-modules/aiida.nix` — the `literalExpression` example.

**Docs and tooling (§7).**

- `Justfile` — `repro-gh` deleted; it existed only to reproduce the failure being removed.
- `docs/TODO.md` — "Allow Python 3.14" replaced by a done record; a new "Port aiida-psi4 off
  QCSchema v1" item; "Stop missing `nix-qchem.cachix.org`" half-closed with a warning that it
  holds by coincidence.
- `AGENTS.md`, `README.md` — attribute spellings and every paragraph asserting a pin. Two
  `AGENTS.md` index rows replaced with ones that point at the absence of a pin and at
  `aiida-psi4`.
- `scripts/{no-daemon-check,locked-nixpkgs,fetch-build-logs,demux-build-log,update-packages}.sh`
  — comments naming the pin or `python3.13-` derivation prefixes.

## Outcome

**Done, and the tree evaluates on 3.14.7.** Verified in-sandbox:

- all four `*-python-pin` tests pass, plus the other three overlay-contract tests
  (`overlay-toplevel-packages`, `overlay-molssi-floors-satisfied`, `overlay-main-programs`,
  `aiida-overlay-toplevel-packages`, `aiida-overlay-pymatgen-override-is-local`);
- cheminformatics 8/8, chemtools 13/13;
- all 15 VM tests instantiate;
- `nix-env -qa --meta --drv-path` over `default.nix` walks all 133 attributes, exit 0 — the
  `just ci-eval` bar;
- `update-universe.nix`'s `missing` is still `[]`, which is what proves the rename did not
  orphan a `pkgs/` directory;
- nixfmt, statix, deadnix and prek clean.

**`aiida-psi4` was the find, and it is the reusable part.** `docs/TODO.md` had said for weeks
that "one package blocks it, and the other three follow it", counted from
`rg -l 'pythonAtLeast "3.14"' pkgs/`. That count was right and the conclusion was wrong:
`aiida-psi4` carried no gate because its failure is not an import failure. The v1 placeholder
is *importable* — that is the entire point of `_make_placeholder`, which exists so that
`import qcelemental` stays clean — and only raises when something instantiates it. So
`pythonImportsCheck` is green and the check phase dies. **Grepping for interpreter gates finds
packages that already know they are broken, not packages that are.** `README.md` and the aiida
overlay comment had both recorded the real reason all along; the TODO item had not.

**The measurement was cheaper than the survey that avoided it.** One
`nix eval --store dummy://` forcing `drvPath` over every `pkgs/` directory against
`python314Packages`, with all overlays composed, answered the "nobody knows what else would
break" question in about a minute: nothing fails to evaluate. The fear was the `e3nn` failure
mode — nixpkgs' 3.14 set missing names the 3.13 set has — and it simply did not materialise.
Same lesson as the `deepmd-kit` / `fairchem-core` rows in `AGENTS.md`: check rather than infer
from reputation.

**The Psi4 cache came back for free**, which nobody was looking for. `flake.nix`'s `qchemPkgs`
rewrites nixpkgs-qchem's `python3` to the worker's interpreter, and the locked `nixpkgs-qchem`
turns out to be 26.11pre-git at 3.14.7 — the same interpreter the repo now follows. The
override is a no-op and `nix-qchem.cachix.org` is live again. `docs/TODO.md`'s "Stop missing
`nix-qchem.cachix.org`" item resolves by its own option 1, but **by coincidence**: neither pin
follows the other, and either can move. The item says so rather than being deleted.

**The cclib trap got worse, not better, and the notes say so.** `final.python3.pkgs` is still
the only set with cclib, and `final.python3Packages` is nixpkgs' alias to the *versioned* set,
which cclib's overlay never touches. Under the pin the wrong spelling was
`final.python313Packages` — visibly different from the house style. Now the house style *is*
`final.python3Packages`, so the wrong answer is one character from the right one everywhere
else and still fails silently, because `cclib ? null` is a defaulted argument.
`cheminformatics-cclib-resolves` is the only thing that catches it. Three notes were
strengthened rather than renamed: `overlays/default.nix`'s harmonwig and
cheminformatics-cclib headers, and the `AGENTS.md` cclib-split section, which lost its
now-redundant first bullet and gained a sentence about why the wrong spelling looks right.

**Rejected: supporting 3.13 and 3.14 side by side.** `docs/TODO.md` framed this as the other
reading of "allow" and argued it was what a consumer on unstable wants. It would mean both sets
exposed, `python314Packages` beside `python313Packages`, and a second copy of every list in the
"three edits" section — four hand-maintained lists becoming eight, with the `*-python-pin`
tests doubled to keep them honest. Following the default was chosen: there is one exposed set,
one copy of each list, and the two interpreters come from the channels rather than from
anything written in the repo.

**Rejected: keeping the `python313Packages` attribute name, or carrying it as an alias.** It is
a breaking change for any consumer spelling `nur.repos.berquist.python313Packages.*`, and an
alias was considered for one release. Both were declined for the same reason: on unstable the
attribute is the 3.14 set, so the name would be a lie either way, and an alias makes the lie
permanent rather than momentary.

**One sandbox limitation, pre-existing.** `scripts/no-daemon-check.sh` reports
`FAIL: could not evaluate` for the qcarchive, aiida and anilist-mal-sync-module suites, on
`path '/nix/store/…-source/nixos/lib/eval-config.nix' does not exist`. This is not caused by
this change: `git archive HEAD | tar -x -C "$TMPDIR/base"` and running the same script there
reproduces it identically on pristine `HEAD`. That trick — a throwaway checkout of `HEAD` from
`git archive`, with no `git stash` and no worktree — is the cheap way to tell a pre-existing
failure from a new one, and is worth reaching for before debugging.

The three suites' *overlay-contract* tests were evaluated directly instead
(`import ./tests/qcarchive { inherit pkgs; }`, then reading each check's `buildCommand` for
`PASS:`), which is exactly what `no-daemon-check.sh` does and skips the `eval-config.nix`
dependency that only the module tests have.

## Round one of the builds

Three failures. Two are `multiprocessing` and 3.14's doing; the third is older than that and
only surfaced now. Fixed in a second commit on top of the pin
change. **The cause of the first two is one CPython change**, read out of the interpreter in the store
rather than from memory — `multiprocessing/context.py:329-332`:

```
# gh-84559: We changed everyones default to a thread safeish one in 3.14.
if reduction.HAVE_SEND_HANDLE and sys.platform != 'darwin':
    _default_context = DefaultContext(_concrete_contexts['forkserver'])
```

The Linux default start method moved from `fork` to `forkserver`.

**`ase-db-backends` — diagnosed and fixed.** `test_aselmdb_concurrent_random_reads` shares one
LMDB handle with eight workers by copy-on-write, and guarded itself with

```python
if mp.get_start_method(allow_none=True) not in (None, "fork"):
    pytest.skip(...)
```

`allow_none=True` returns `None` when nothing has set a method *explicitly*; it does not
resolve the default. So `None` never meant "fork" — it meant "nobody has chosen" — and reading
it as fork was correct only while fork was the platform default. On 3.14 the guard still sees
`None`, still declines to skip, and `mp.Pool()` builds forkserver workers that never inherit
the module-level `DB`: `AssertionError: Global DB handle not set in worker`. **The test's own
skip condition is what broke, not the code under test.**

Verified on the real 3.14 interpreter, in fresh processes (asking `allow_none=True` *first* —
calling `get_start_method()` beforehand populates `_actual_context` and contaminates the
answer, which cost one wrong reading here):

| probe | answer |
|---|---|
| `mp.get_start_method()` | `forkserver` |
| `mp.get_start_method(allow_none=True)` | `None` |
| old guard skips? | `False` — so it runs, and fails |
| new guard skips? | `False` — correct, it should run on Linux |
| `mp.get_context("fork").Pool` workers see the global | `['handle', 'handle']` |

`pkgs/ase-db-backends/fork-context-not-default.patch` asks for a fork context explicitly and
rewrites the guard to "is fork available and safe here" (`sys.platform != "linux" or "fork" not
in mp.get_all_start_methods()`). Skipping on 3.14 was the alternative and was rejected: this is
the only test that exercises reinitialising the LMDB environment in a forked child — the thing
`close-must-not-reopen.patch` is about — and its own comment says it "will very likely
segmentation fault" if that is wrong. Losing it on every future interpreter is worse than the
bug. Upstream defect, worth sending on, like the `close()` one beside it.

**`fireworks` — one wrong hypothesis, then the real cause.** `TrackerTest::test_tracker_mlaunch`
fails `assert '' == '48\n49'`, which says only that no rocket ran. The reason looked unavailable
because the test discards it:

```python
try:
    launch_multiprocess(self.lp, self.fworker, "ERROR", 0, 2, 0, ppn=2)
except Exception:
    pass
```

So the first move was a diagnostic patch unguarding that call, on the theory that an exception
was being hidden. **It was not.** The rebuild shows `launch_multiprocess` returning cleanly,
logging nothing, raising nothing, and running no rockets — identical failure. The patch did its
job by proving the negative, and was then dropped rather than kept: it would have added risk to
a green 3.13 leg for no present gain.

In hindsight the theory could not have been right, and the code says so:
`launch_multiprocess` ends in `for p in processes: p.join()`. **A child process that finds no
work — or dies — is not an exception in the parent.** Reading the function before patching
would have ruled out the swallow as the suspect. Worth remembering: a bare `except: pass` is
conspicuous enough to look like the answer, and the join loop three lines below it was the
thing actually worth reading.

The real cause is this repository's mongomock stand-in meeting upstream's launcher, and neither
half is wrong on its own. `DataServer.setup()` pickles a `_LaunchPadCallable` into the manager's
server process — deliberately; `fw_utilities.py:219` says "Use a picklable callable class for
spawn-based multiprocessing compatibility". That is correct against a real MongoDB, whose
reconstructed client reaches the same server. It is wrong against mongomock, whose "server" is
memory local to the process that made it. Measured on 3.14, with a workflow already added, using
the real fireworks and mongomock out of the store:

| path | `fw_ids` seen |
|---|---|
| parent, after `add_wf` | `[1]` |
| `MONGOMOCK_SERVERSTORE_FILE` on disk at that moment | `{}` |
| rebuilt from pickle — what forkserver/spawn does | **`[]`** |
| forked child — what 3.13 did | `[1]` |

A LaunchPad pickles to **274 bytes** of connection parameters, so the rebuilt one opens an empty
database. The serverstore file is mongomock's only cross-process channel and, per the
derivation's own note, is written when a client is *finalised* — the parent's is still live, so
it is still `{}`. The rapidfire children ask an empty LaunchPad for fireworks, get none, and
exit cleanly.

The in-process `pickle.loads(pickle.dumps(lp))` round-trip is the whole demonstration and needs
no second process at all, which is worth knowing: the sandbox blocks the AF_UNIX sockets
`forkserver` needs, so the obvious experiment is unavailable and the cheaper one is stronger.

Fixed by `pkgs/fireworks/conftest.py`, copied in by `preCheck` — upstream ships no conftest —
forcing `fork` for the whole session. Every FireWorks test crossing a process boundary shares
the constraint, because they all share the mock database, so this belongs to the session rather
than to one test. It is a property of building without a real MongoDB, not of FireWorks, which
is why it is a conftest and not a patch to upstream's code. A real server stays out of reach:
mongodb-ce is SSPL, `meta.license.free = false`, and `ci.nix` filters on that — which is the
whole reason mongomock is here.

This knowingly buys back the threaded-fork hazard 3.14 moved away from. That is what every green
FireWorks build before 3.14 was doing, and the conftest header says so rather than pretending
otherwise.

**`nvalchemi-toolkit-ops` — one failure in 6257, and the first of these that is *not* a 3.14
bug.** `TestBatchedCalculations::test_two_independent_batches`, under 32 xdist workers:

```
assert torch.allclose(forces[0], forces[2], rtol=1e-10)
  forces[0] = tensor([1., 0., 0.])
  forces[2] = tensor([nan, nan, nan])
```

The test declares two batches and supplies one cell, and the kernel indexes the cell per atom
(`coulomb.py:453-456`):

```python
system_id = batch_idx[atom_i]          # batch_idx = [0, 0, 1, 1]
cell_t = wp.transpose(cell[system_id]) # cell.shape == (1, 3, 3)
```

Atoms 2 and 3 read `cell[1]` of a length-1 array, which warp does not bounds-check in release
mode.

**Why it was invisible for so long is the part worth keeping.** The cell reaches the arithmetic
only through the periodic shift, and every shift in these tests is zero:

```python
shift_vec = cell_t * type(ri)(unit_shifts[edge_idx])
r_ij = ri - rj - shift_vec
```

`0 * garbage` is `0` while the garbage decodes as an ordinary double, so the out-of-bounds read
costs nothing. When those bytes decode as NaN or inf it is `0 * NaN`, and then `r = NaN`, the
guard `if r >= cutoff or r < 1e-10` is False for NaN, and the NaN reaches the force accumulator.
Batch 0 is right because `cell[0]` is real; batch 1 is NaN because `cell[1]` is not.

So the outcome depends on what happens to sit past the end of a tensor. **This is not a 3.14
regression and not a platform one** — it can flip on any leg and any run, and being spread over
32 xdist workers makes the memory state less predictable still. It had simply been winning the
coin toss.

An AST scan of the suite for tests whose `batch_idx` implies more batches than their `cell`
provides found three, all in `test_coulomb.py`, all identical:

| test | cells | batches | this run |
|---|---|---|---|
| `test_two_independent_batches` | 1 | 2 | **failed** |
| `test_batched_with_damping` | 1 | 2 | passed, by luck |
| `test_batched_autograd` | 1 | 2 | passed, by luck |

`test_batch_momentum_conservation`, in the same class and also two batches, already supplies a
cell per batch. `pkgs/nvalchemi-toolkit-ops/batched-cell-out-of-bounds.patch` makes the other
three match it — targeted at those three line numbers, because the same single-cell literal
appears 46 times in the file and 43 of them are single-batch tests where one cell is correct.
Rescanning the patched copy reports no remaining mismatches.

Deselecting was the alternative and was wrong: the tests are correct in intent, and the two
that passed would have stayed as time bombs. Also worth sending upstream is the observation
that nothing validates `cell.shape[0]` against `batch_idx.max()`, so a caller making this
mistake in earnest gets silent corruption rather than an error — but that is a library change,
not attempted here.

The derivation's `disabledTests` note claimed its one entry was "the only failure in the whole
8129-item suite that a CUDA device would not have fixed". That is now wrong on both counts —
this is a second, and the suite collects 6257 items here — and the note says so.

## Follow-ups

- **Confirm all three fixes build.** None has been through a real build: the
  `ase-db-backends` guard, the FireWorks conftest and the `nvalchemi-toolkit-ops` cell patch
  were verified by running the interpreter directly and by re-scanning the patched sources,
  not by `nix build`.
- **Finish the builds.** `just ci-matrix` with `--keep-going`, then `just build-logs`. 121
  packages have never been compiled on 3.14 and evaluation says nothing about that. The 26.05
  leg is 3.13.15 and should be unaffected; the two unstable legs are the ones to watch. Two
  failures in round one is well inside what the sdist-has-no-tests experience budgets for.
- **Proposal: gitignore the build logs.** `just build-logs` writes `log-<name>-<hash>` files
  into the working directory and `just ci-build 2>&1 | tee log_ci_matrix` leaves that beside
  them, and `git check-ignore` matches neither — so both sit untracked where `git add -A` would
  sweep them into a commit. A `log-*` / `log_ci_matrix` pair of lines in `.gitignore` looks
  right. Not done unasked.
- **Port `aiida-psi4` off QCSchema v1**, per the new `docs/TODO.md` item. It is the only
  package now carrying a 3.14 gate.
- **Watch the two-interpreter matrix.** A failure on two legs out of three is now an
  interpreter difference, not a dependency one. `default.nix`'s `py` comment and `docs/TODO.md`
  both say to mark the package rather than re-pin the repository.
- **Proposal, from the repeated-command pass** (`./scripts/sandbox-eval.sh` 14×,
  `nixfmt`/`statix`/`deadnix` 12/8/9×, `prek` 11×, `./scripts/no-daemon-check.sh` 3×): the
  recurring ones all already have recipes — `just eval`, `just fmt`, `just lint`, `just hooks`,
  `just check-no-daemon` — and were only spelled out longhand because the devShell is
  unreachable from the sandbox (`nix develop` dies on
  `unsupported extension name extensions.refstorage`). Nothing new belongs in the `Justfile`.
  What *would* help is a note in the `no-daemon-check` skill recording where `nixfmt`, `statix`,
  `deadnix` and `prek` live in the store when the devShell cannot be entered, and that `prek`
  needs `XDG_CACHE_HOME` and `PREK_HOME` pointed at `$TMPDIR` because `~/.cache` is read-only
  there. Each of those cost a round trip this session.
