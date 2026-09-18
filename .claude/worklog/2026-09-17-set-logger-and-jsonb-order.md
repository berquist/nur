---
date: 2026-09-17
slug: set-logger-and-jsonb-order
status: done
sessions: ["cf9a5c57-c4c9-40fa-93cd-40911749921f"]
touches:
  - "pkgs/aiida-psi4/**"
  - "pkgs/aiida-workgraph/**"
  - "pkgs/aiida-core/**"
---

# Two build logs, two upstream renames

The last two failures of `log_ci_matrix`'s first leg (`nixpkgs-unstable`, 26.11pre-git), read
from the per-derivation logs `scripts/fetch-build-logs.sh` had left in the working directory.
Eleven test failures in `aiida-workgraph` and one in `aiida-psi4`, and in both cases the whole
thing was a single renamed name in the staged aiida-core bump — `e56a9068` (2026-08-16) to
`e4d99200` (2026-09-12), the revision that absorbed plumpy and kiwipy.

## Ask

> read every file in the workding directory that is prefixed with "log-"

> I asked you to read them because I want you to use these results to add patches to the Nix
> packages so they build

> yes, write the worklog

## Plan

No plan mode this session. The first prompt was a read; the second turned it into a task, and the
work was two independent diagnoses with no shared structure to plan around.

## Out-of-band

No commands run through `!`.

The staged tree was committed from another terminal partway through — `9d0fdf9 update aiida
versions`, which swept up this session's two edits along with the rest of the in-flight AiiDA
migration. That commit is in git, so nothing is lost, but the act itself is not in the transcript;
running it through `!` is what would have made it recoverable.

## Changes

`9d0fdf9`, both files, alongside the pre-existing staged migration:

- `pkgs/aiida-workgraph/default.nix` — one `substituteInPlace` hunk rewriting
  `self.set_logger(...)` to `self._set_logger(...)` in `engine/workgraph.py`, plus the note
  explaining why one renamed method cost ten tests.
- `pkgs/aiida-psi4/default.nix` — the existing `examples/example_01.py` hunk gains a `jsonb_order`
  helper applied before `set_dict`, plus the note on why the mock-code digest went stale again.

## Outcome

### aiida-workgraph: 11 failures, one rename, and only on the daemon path

The log's failures looked like four unrelated defects — `assert None == 5`, `assert None == 302`,
`'No log messages recorded for this entry'`, and an `AttributeError: 'AiiDAFunctionTask' object
has no attribute 'node'`. What made them one thing was a partition that holds without exception:
**every non-skipped test that calls `wg.submit()` fails; every test that calls `wg.run()` passes.**
`tests/test_yaml.py`'s lone submit is `@pytest.mark.skip`, and `test_workgraph.py::test_reset_message`
is already deselected, which is why the count comes to exactly the eleven observed.

The one code path `submit` takes and `run` does not is checkpoint deserialisation: a daemon worker
recreates the process by calling `load_instance_state`. aiida-core's `df3df5cc4` ("Remove
ineffective protected decorator", #7607) renamed the non-public `Process` methods to carry a
leading underscore — `set_logger`, `log_with_pid`, `encode_input_args`, `decode_input_args` —
"while preserving public APIs such as `out()` and `load_instance_state()`". It updated its own
`WorkChain`, which makes the identical call one line from where aiida-workgraph makes it. Nothing
updated the plugins.

`rg '\.set_logger\(' wc/ -g '*.py'` finds one call site in the whole family, and it is inside
`load_instance_state`. The AttributeError is raised in the worker, so it excepts the process rather
than surfacing anywhere the test can see — and an excepted process is terminal with no report and
no `exit_status`, which is what turned one defect into four symptoms. The four timeouts
(`test_task_pause_play`, `test_task_kill`, `test_pause_play_task`, `test_task_monitor_kill`) are
the same thing from the other side: they wait on a *task* state only a running graph reaches.

The `AiiDAFunctionTask` AttributeError is **not** an API break, though it reads exactly like one:
`Task.update_state` assigns `self.node` only when `data['pk'] is not None`, so a graph that never
ran leaves the attribute unset.

**Four hypotheses tried and discarded before this one** — each cost real time, and re-proposing any
of them would waste it again:

- *A missed plumpy/kiwipy import.* Plausible shape (a module imported only on the daemon path would
  fail exactly this way), but `rg 'plumpy|kiwipy|aiida_shell' src/ tests/` shows the staged
  `postPatch` covers every one.
- *The `Protect` metaclass removal.* `Protect` is genuinely gone from aiida-core, and the rewrite to
  `class WorkGraphEngine(Process)` / `@t.final` is correct; `Process` supplies its own metaclass.
- *The new checkpoint API.* `8cad70e2d` renamed `Bundle`/`Savable`/`LoadSaveContext`/`Persister`,
  but `save_instance_state` and `load_instance_state` kept their names and signatures, and
  aiida-workgraph types the context as `t.Any` — so its overrides were never at risk.
- *The daemon restart killing the ZeroMQ broker.* The most seductive one, and worth recording in
  full because the mechanism is real. `d432059b9` made `started_daemon_client` stop and restart the
  daemon before every test, and `ZeromqBroker`'s `supervised_by_daemon` defaults to `True`, which
  runs the broker as a circus watcher *inside* the daemon — so a restart would destroy the broker
  the test process holds a cached communicator to. It is not what happened: `aiida.tools.pytest_fixtures`
  ships a session-scoped `autouse` fixture, `run_aiida_broker_service`, that starts a standalone
  broker for any `core.zeromq` profile, and `_start_daemon` skips its own watcher when it finds one
  already reachable. The tell that killed this theory was timing: `test_decorator_calcfunction`
  failed on an *assertion* inside its 100-second budget, not on a `TimeoutError`, so the process
  did reach a terminal state — a graph nobody picked up would have hung instead.

That last point is the generalisable one. **An excepted process and an unadopted process look alike
in a test that asserts on outputs, and the way to tell them apart is whether the wait returned or
timed out.** `test_failed_node`'s `exit_status is None` is the cleanest single confirmation: an
excepted process has no exit status, a failed one has 302.

Expect this to reveal the next layer. The two CLI race tests that `await-daemon-adoption.patch`
exists for cannot be reached at all while submission is broken, so that patch is untested against
this aiida-core. The `--numprocesses` note above `patches` — the one about 32 workers failing and
128 passing — no longer describes the current failures; it was left in place and cross-referenced
rather than rewritten, because re-measuring it needs a build.

### aiida-psi4: jsonb key order, not qcelemental

`examples/example_01.py::test_run` died on `KeyError: 'qcschema'` with the parser reporting only
the two `_scheduler-*.txt` files — the signature of a mock-code digest that describes nothing.
The derivation's existing note blames the qcelemental version, and that was the wrong suspect:
the locked nixpkgs still has 0.50.4, exactly what the provenance pin names.

The real cause is the staged fixture migration in the same commit. Moving from
`aiida.manage.tests.pytest_fixtures` to `aiida.tools.pytest_fixtures` moves the profile from
`core.psql_dos` to `core.sqlite_dos`, and `_write_input_file` does a bare
`json.dumps(self.inputs.qcschema.get_dict(), indent=2)` with no `sort_keys`. Postgres `jsonb`
orders an object's keys by byte length then bytewise; SQLite stores plain JSON and echoes back
insertion order. Different bytes, different md5. Same category as the `aiida-orca` and
`aiida-siesta` `regen-stale-fixtures.patch` files staged alongside.

**`example_02` is the control that makes this airtight.** Its working directory is
`_aiidasubmit.sh` plus a literal PsiAPI string with no dict in it, and its digest still hits
across both the storage-backend change *and* the aiida-core bump. So the submit script is
unchanged and key order is the whole of the difference — which is what made it safe to fix the
input rather than re-record the digest.

Two things checked locally rather than assumed, both without a daemon:

- The recorded `tests/data/mock-psi4-1.4rc2-8ee90fe.../input.json` **is** jsonb order at every
  level (`id`, `model`, `driver`, `extras`, `keywords`, `molecule`, …). Feeding it through a
  shuffle and back through the ordering function reproduces the file byte for byte.
- Building the input the way the patched example does, against the store's qcelemental 0.50.4,
  produces a file differing from the recorded one only in the three expected places — two
  `version` strings and one `routine` path. So `24adc79085d1b8f0d854137ffa8076e6` should hit again.

The ordering is idempotent under psql_dos, so this survives a move back — which is the reason to
prefer it over re-recording. `key.encode()` rather than the bare `str` because jsonb orders by
UTF-8 byte length; every key here is ASCII, so it changes nothing today and stops a non-ASCII key
added upstream from sorting differently from the database that recorded the fixture.

`aiida_testing.mock_code._cli.get_hash` is worth knowing directly, and is readable from any
built store path: md5 over `sorted(Path('.').glob('**/*'))`, each file contributing
`path.name` then its content, with `_aiidasubmit.sh` first stripped of its `AIIDA_MOCK` exports
and the mock binary's abspath. That is what makes the working directory's *byte* content, not its
semantics, the thing the digest is over.

### What was verified, and what was not

`just check-no-daemon` passes and both files are nixfmt-clean. Neither check phase was run: the
sandbox blocks `socket(AF_UNIX)`, so `nix build` fails with `cannot create Unix domain socket`
before it starts.

To compensate, both evaluated `postPatch` scripts were replayed against the real upstream trees in
`wc/` under a twelve-line `substituteInPlace` shim that reproduces `--replace-fail`'s
pattern-not-found abort. Every anchor matched and every patched module parses under `ast.parse`.
That does not prove the tests pass, but it does rule out the failure mode that would otherwise
waste a whole build — a stale anchor aborting `patchPhase`.

## Follow-ups

- **Neither fix has been built.** `just build aiida-workgraph && just build aiida-psi4` is the
  outstanding confirmation. Expect workgraph's two CLI race tests to reappear once submission
  works, since they have not run against this aiida-core.
- **The `--numprocesses` note in `pkgs/aiida-workgraph/default.nix` is stale** as an account of
  current failures. Once a build gets past the `_set_logger` fix, re-measure whether the 32-vs-128
  behaviour it describes still holds, and rewrite or delete it.
- **Capturing repeated commands** — a new one, and a third instance of an old one:
  - *New.* Replaying an evaluated `postPatch` against its `wc/` clone under a `substituteInPlace`
    shim was invented this session and used for both packages. It catches a dead `--replace-fail`
    anchor with no daemon, which is otherwise a failed `patchPhase` several minutes into a build.
    Proposal: `scripts/replay-postpatch.sh <attr> <clone>` plus a one-line `just` recipe, in the
    spirit of `scripts/sandbox-eval.sh`. It composes with `just channel-gaps` — both answer
    "would this build get off the ground" without building.
  - *Third instance.* `export PATH="$(scripts/sandbox-path.sh)"` prefixed 102 of this session's 104
    Bash calls, and `nixfmt` again had to be hunted out of `/nix/store` by hand because the devShell
    is unreachable. [2026-08-30](2026-08-30-materials-jobflow-chain.md) and
    [2026-09-14](2026-09-14-updater-scan-speed.md) both proposed fixing this and neither was taken
    up; [2026-09-14 ci-matrix](2026-09-14-ci-matrix-six-rounds.md) proposed extending
    `sandbox-path.sh` to the devshell formatters. Nothing new to add to the analysis — only that it
    has now recurred often enough that the cost is no longer speculative.
- **The `set_logger` rename is family-wide in principle.** `rg '\.set_logger\(|log_with_pid|encode_input_args|decode_input_args' wc/ -g '*.py'`
  finds only aiida-workgraph today, but the same sweep is worth repeating after the next aiida-core
  bump — the rename commit's own message is the list of what moved.
