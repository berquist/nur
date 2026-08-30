---
date: 2026-08-30
slug: materials-jobflow-chain
status: partial
sessions: ["d1da8cd9-e73f-4df8-8bf7-5d2569a4b15e"]
touches:
  - "pkgs/fireworks/**"
  - "pkgs/qtoolkit/**"
  - "pkgs/mongomock-ng/**"
  - "pkgs/maggma/**"
  - "pkgs/jobflow/**"
  - "pkgs/jobflow-remote/**"
  - "pkgs/molcat/**"
  - "ci.nix"
  - "flake.nix"
  - "overlays/default.nix"
  - "default.nix"
  - "tests/chemtools/default.nix"
  - "AGENTS.md"
---

# The jobflow chain, and four things MongoDB's licence decided

## Ask

Verbatim and in order. No plan mode was used; the session was driven prompt by
prompt, with the user running each build in a separate terminal and handing back
a log.

> read "log-fireworks" and fix the problems. i'd also like to know why some tests were skipped.

> does it make sense to have a fireworks module?

> first I want to know why ci is blocked on unfree.  I think it was there in the NUR template but I can't think of a reason to keep it

> I deleted molcat since its upstream was removed. Does this change any of the reasoning?

> yes

> once you're done I want to revisit the problems of creating a service for fireworks

> 1. I care about having the host for mongodb be somewhere, not so much the lpad webgui.  Maybe I'm misunderstanding how fireworks works.  2. I don't see the value in that.  3. I guess I wanto to package jobflow/jobflow-remote/atomate2, so tell me what I need to clone in order to start on that.

> yes, fix the Deferred packaging section and then get started

> read "log-qtoolkit".  I've cloned both repos.

> read "log-qtoolkit" again

> continue

> read "log-maggma"

> read "log-maggma"

> continue

> continue

> read "log-jobflow-remote"

> continue

## Plan

None. No `ExitPlanMode` in the transcript and no plan file — the shape came out
of the first three prompts and then ran on `continue`.

## Out-of-band

The user ran every `nix build` themselves, in a separate terminal, and handed
back a redirected log: `log-fireworks`, `log-qtoolkit` (twice), `log-maggma`
(twice) and `log-jobflow-remote`. None of those invocations is in the
transcript, so the exact commands are not recoverable — only their output, and
only for as long as the files sit in the working tree. Running them through `!`
in the prompt instead is what would make them recoverable next time.

They also did the git work: eight commits, and the two clone rounds
(`maggma`, `qtoolkit`, `emmet`, `pymatgen`, then `mongomock-ng` and
`pymatgen-core`).

The double `read "log-<x>" again` prompts were not repetition — in both cases
the log had been regenerated between the two reads and showed a different
failure.

## Changes

Eight commits, `8435495..5625816`.

| Commit | Why |
|---|---|
| `15ef6b8` | fireworks: drop `pytest-xdist`, deselect two `WFLockTest` tests |
| `f843664` | (user's) remove molcat, upstream deleted |
| `feea671` | molcat's leftovers, the cclib count, and a note on `ci.nix`'s unfree filter |
| `2700d63` | qtoolkit, and the corrected deferred-packaging survey |
| `d86ebcb` | qtoolkit: `procps` and `numpy` |
| `c264232` | mongomock-ng and maggma |
| `4355c5b` | jobflow |
| `5625816` | jobflow-remote |

Five new packages: `qtoolkit`, `mongomock-ng`, `maggma`, `jobflow`,
`jobflow-remote`. Four are re-exported; `mongomock-ng` stops at the overlay as
maggma's private dependency, beside `mongomock-persistence`.

## Outcome

### fireworks: xdist made it worse, and the runtime was two tests

`pytest-xdist` in `nativeCheckInputs` is not inert. nixpkgs' `pytest-xdist`
ships a setup hook that appends `--numprocesses=$NIX_BUILD_CORES` by itself, so
the dependency alone switched the suite to `--dist load` over 128 cores. That
took a green run to 20 failed / 7 errors, through three kinds of shared state:
`CompressDecompressArchiveDirTest` gzips every file in the `firetasks/tests`
package while other workers are importing it, `SerializationTest` races on a
`./test.json` in the shared build directory, and the workers race on one
`MONGOMOCK_SERVERSTORE_FILE`.

**`--dist loadfile` was tried and rejected.** It keeps the suite green and buys
nothing — 110.6s against 110.1s serial — because `test_launchpad.py` alone is
108s of the suite. Do not re-propose it.

The actual runtime was two tests. `WFLockTest.test_fix_db_inconsistencies_*`
wait out three timeouts (10s + 10s + 20s) for a lock taken by a
`multiprocessing.Process` whose forked mongomock the parent can never see, then
**skip themselves** through the test's own escape hatch. 90 of 110 seconds, for
no coverage. Deselecting them: 110s → 20s, same 155 passing.

The eight skips the user asked about, from `-rs`: three `AuthenticationTest`
(our own `MONGOMOCK_SERVERSTORE_FILE` makes `_is_mongomock()` true), three
`LaunchPadLostRunsDetectTest` (gated on pymongo ≤ 3, nixpkgs has 4.17.0), and
the two `WFLockTest` above. A ninth skip in the older run,
`test_getfilesbyquerytask_run`, had moved to *deselected* when `disabledTestMarks`
landed.

### ci.nix's unfree filter: template-verbatim, and worth keeping anyway

The user's recollection was right — `git show d53235b:ci.nix` has the licence
half of `isBuildable` character for character. But it is not a policy filter, it
is a throw guard: nixpkgs refuses to *evaluate* an unfree package, `cacheOutputs`
is what `just ci-build` forces, and nothing sets `allowUnfree`, so one unfree
attribute costs the entire cache-population build rather than one package.
`--keep-going` does not help, because it is an eval error.

Measured before and after molcat's removal: `excludedByLicenceAlone` was `[ ]`
both times — molcat was already `broken = cclib == null` on the NUR path — and
is now `[ ]` with nothing unfree at all. So the guard is inert. **Kept anyway**,
on the asymmetry: four lines against a failure that takes out the whole build
set at the moment a package is added, in a domain that demonstrably produces
unlicensed code (molcat had no LICENSE file at all). Its reach is narrow and now
says so: it reads `meta.license` of top-level `default.nix` attributes only, not
dependencies, not the VM tests, not `ci-eval`.

molcat's removal left three stale `AGENTS.md` references, two pointing at a
deleted file. Fixed, along with a pre-existing drift: the cclib section claimed
six packages take `cclib ? null` and tabled seven, where `rg -l` finds ten.

### fireworks as a NixOS module: no

The user's "maybe I'm misunderstanding how fireworks works" was the opposite of
the truth. **There is no FireWorks server.** The LaunchPad *is* the MongoDB;
`lpad`, `rlaunch` and `lpad webgui` are all clients that open their own
`MongoClient`. So "the host for mongodb" is the entire server side, and
`services.mongodb` already exists in nixpkgs. A module would be a YAML renderer
plus `rlaunch` units — 150–200 lines against the existing 572–1171 — and its VM
test could not run in `nix flake check` without `allowUnfree`.

**Rejected.** An earlier answer in the same session had mapped `lpad webgui`
onto `qcfractal-server`; that overstated it, since the webgui is a dashboard
nothing depends on. `jobflow-remote` is the module worth writing instead: it has
a real supervisor-backed daemon in `jobs/daemon.py`, driven by `jf runner`.

### The deferred-packaging survey was wrong three ways

Rewritten from the targets' own `pyproject.toml` rather than memory:

- **Seven missing packages in two layers**, not six. `maggma`, `qtoolkit`,
  `emmet-core`, `pymatgen-core`; then `mongomock-ng`, `pubchempy` and
  `pymatgen-io-validation`, which only surface once the first layer is read.
- **`mp-pyrho` and `mp-api` are not on this path.** `mp-pyrho` belongs to
  `pymatgen-analysis-defects`, `mp-api` to `matcalc` and atomate2's optional
  `mp` extra.
- **"a pymatgen bump" understates it badly.** pymatgen is now a metapackage whose
  sole dependency is `pymatgen-core`; the code moved to its own repository,
  carried as a git submodule (which is why a `--depth 1` clone leaves
  `pymatgen-core/` empty). nixpkgs is on the pre-split 2025.10.7 monolith owning
  the same import paths, and atomate2 asks for both names at once — so
  `pymatgen-core` *replaces* nixpkgs' pymatgen rather than joining it.

### Five packages, and what each cost

**qtoolkit** — `dependencies = []`, so it went first. Two build rounds:
`pydantic`, undeclared in any extra but imported directly by
`TestQEnum::test_serialization`, which is guarded on monty rather than on
pydantic and so fails instead of skipping; and `procps`, because `ShellIO`
builds a literal `["ps", …]` argv. The `"ps"` literal was deliberately **not**
rewritten to a store path — `ShellIO` also runs over a fabric connection to
another machine, where a path into this closure names nothing.

**versioningit, three times.** `method = "git"` against a `fetchFromGitHub`
tarball. `default-tag`, which all three set, is not the escape — it applies only
when the repository exists and is untagged. The top-level `default-version` is,
and none of them declares the table, so `postPatch` inserts it *ahead* of the
`vcs` sub-table (TOML parent tables cannot follow their children). Verified by
rendering the string and running versioningit against a `.git`-less tree.

**mongomock-ng** — a *third* mongomock, not a version of either already here;
the import path is `mongomock_ng`, so it collides with neither nixpkgs'
`mongomock` nor our `mongomock-persistence`. `NO_LOCAL_MONGO=1` is upstream's
own switch, read by four test modules and set by their CI: without it twelve
tests spend 30s each in pymongo server selection and then fail, 6:27 of a 6:29
suite. With it, 1317 passed in 2.1s.

**maggma** — its suite has no offline mode at all; upstream CI brings up
`mongo:5.0` and Azurite. Eight modules disabled. Two build rounds:

- `paramiko>=5.0` against 26.05's 4.0.0. Relaxed, and the measurement was not
  the expected one: the abstract `paramiko.PKey.from_private_key_file` the pin
  was raised for raises `TypeError` on **5.0.0 and 4.0.0 alike**, for RSA and
  Ed25519 both. The auto-detecting entry point is `PKey.from_path`, which
  upstream did not use. The pin buys nothing.
- Two `test_aws.py` tests that take a `mongostore` fixture. **`disabledTestPaths`
  with a `::` entry silently does nothing here**, and this is the one package in
  the repo where that is true: `tests/conftest.py` rewrites `item._nodeid` in
  `pytest_itemcollected` for prettier output, and `--deselect` is applied
  afterwards in `pytest_collection_modifyitems`, against the rewritten value.
  `disabledTests` (`-k`) matches `item.name`, which the hook leaves alone.
  Verified against a reduced copy of that conftest: `--deselect` left 3 of 3
  running, `-k` deselected 2.

**jobflow** — clean first time, 139 passed. **`fireworks` is deliberately not a
check input**, inverting this repo's usual rule: `tests/managers/test_fireworks.py`
opens with `pytest.importorskip("fireworks")` and its seventeen tests want a real
LaunchPad, so installing fireworks turns one clean skip into seventeen
`ServerSelectionTimeoutError`s. What is missing is the database, not the library.
Measured both ways: 139/4 skipped against 141/3 skipped/**17 errors**.

**jobflow-remote** — excluded `tests/db` and `tests/integration` **by path, not
by marker**, though upstream maintains exact `unit`/`db`/`integration` markers.
Marker filtering runs after collection, collection imports the module, and
`tests/integration` imports `python-on-whales` at module scope; `--ignore-glob`
is applied first. `pymongo >= 4.4, < 4.11` relaxed against 4.17.0: the bound
arrived as an undocumented Feb-2025 "hot fix", and the circumstantial answer is
old mongomock, which caps pymongo the same way — maggma carried the identical
bound until it switched to mongomock-ng expressly to drop it. There is also no
version that satisfies everyone, since `mongomock-ng` wants `>= 4.11`. The one
test failure was upstream's own stale `assert __version__.startswith("0.")`
against a package at 1.0.1; rewritten to compare against the exact version
rather than deselected, because it then doubles as the check that the
versioningit fallback did not silently produce `0.0.1`.

### The pattern worth naming

Five packages, and MongoDB's SSPL licence shaped four of them — fireworks,
mongomock-ng, maggma and jobflow. The argument now lives in fireworks' comment
and is cross-referenced from three others.

The 26.05/unstable channel split bit three times independently: monty's numpy
(propagated on unstable, not on 26.05), paramiko 4 vs 5, and monty itself.
A local harness resolving one channel cannot see the other's failures.

## Follow-ups

- **Capture the offline pytest harness.** `mkpath.py` (17 uses) and `pick.sh`
  (7) walked `nix-support/propagated-build-inputs` to build a `PYTHONPATH` from
  store paths, letting a package's suite run with no daemon. It found
  qtoolkit's `pydantic`, mongomock-ng's `NO_LOCAL_MONGO`, jobflow's fireworks
  interaction and maggma's `--deselect` trap — everything the build logs later
  confirmed, minus two round trips each. It lives in `$TMPDIR` and will be lost.
  Proposal: `scripts/offline-pytest.sh <pkg-attr> [pytest args]` plus a `just`
  recipe, with the `git archive`-to-tmpdir and the synthetic `.dist-info` that
  `importlib.metadata` needs. **Its one blind spot is worth documenting too**:
  it resolves whatever is already in the local store, which is one channel, and
  it inherits a PATH the builder does not have — which is exactly how qtoolkit's
  `procps` and maggma's paramiko got missed.
- **Reach the devShell tools from the sandbox.** `nixfmt` was invoked 37 times
  and `prek` 14, every one by hardcoded store path, because `nix develop` cannot
  open this repo under the sandbox's libgit2 ("unsupported extension name
  extensions.refstorage") and so `just fmt` / `just hooks` do not work there.
  Proposal: extend `scripts/sandbox-path.sh`, or add a sibling, to resolve
  `nixfmt`, `statix`, `deadnix` and `prek` the same way it resolves the base
  PATH.
- **Promote the MongoDB argument out of `pkgs/fireworks`.** It now governs five
  packages and gets cross-referenced from four. A short `AGENTS.md` section
  would stop it being rediscovered a sixth time.
- **atomate2 is next, and needs two clones first**: `pubchempy` and
  `pymatgen-io-validation`, both `emmet-core` dependencies. `emmet-core` can be
  built against nixpkgs' pre-split pymatgen, so it need not wait for the split.
  `pymatgen-core` should be its own session.
- `just check-no-daemon` (13 uses) and `just hash-src` (5) are already recipes
  and worked throughout; no change wanted.
