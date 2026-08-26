---
date: 2026-08-25
slug: ci-matrix-green
status: done
sessions: ["453b297a-dd64-43ba-a71d-2fcd5f2a2f63"]
touches:
  [
    "pkgs/aiida-core/**",
    "pkgs/aiida-psi4/**",
    "pkgs/plumpy/**",
    "pkgs/pycifrw/**",
    "overlays/default.nix",
    "nixos-modules/qcfractal-compute.nix",
    "flake.nix",
    "tests/qcarchive/default.nix",
    ".github/workflows/build.yml",
    "README.md",
    "system-flake-snippet.nix",
  ]
---

# `just ci-matrix` green on all three channels, and the QCFractal interpreter skew

Eleven commits, `183579d..7c8965e`, over about 24 hours. Two unrelated bodies of work in one
session: a Python-version skew in the QCFractal compute module plus the cachix wiring
(`183579d`, `e9ff53e`, `96202ea`), then eight commits driving the AiiDA ecosystem to a green
`ci-matrix` across `nixpkgs-unstable`, `nixos-unstable` and `nixos-26.05`.

## Ask

Verbatim and in order. `/compact` fired three times; the work either side of each is continuous.

> read "vm-test-run-qcfractal-compute-singlepoint"

> can you find where in the "git diff origin/main HEAD" the problem was introduced?

> fix the version check to reject the program too.  I will make a later PR for Python 3.14 since the latest versions of the QCArchive ecosystem all support it.

> now I want to have them use the same interpreter.  I believe all the QC programs should be using the compute worker's interpreter.

> set up the repo to use a personal cachix cache and tell me what actions I need to do on the web

> the public key is "nur-berquist.cachix.org-1:Hoz7CuoAaFYOUxiy5zcrHEM82xJKjilI24ly0W+1kq4="

> "just check 2>&1 | tee log_check" is clean. does that mean the requested AiiDA work is done?

> "just ci-build 2>&1 | tee log_ci" is clean.  "log_ci_matrix" isn't

> yes, make the change

> read "log_aiida"

> yes, make the fix

> read "log_ci_matrix" and "log_aiida"

> yes, write the plumpy patch

> read 'log_aiida' again

> write them

> read 'log_ci_matrix' and 'log_aiida' again

> read 'log_ci_matrix' and 'log_aiida' again

> remove the shared state

> read 'log_ci_matrix' again

> the above nix-instantiate command gave '{ }'

> read 'log_ci_matrix' again

> read 'log-monty' and 'log_ci_matrix' again

> read 'log_aiida' and 'log_ci_matrix' again

> read 'log_aiida' and 'log_ci_matrix' again

> read 'log_aiida' and 'log_ci_matrix' again

> the ci matrix now passes. now read "log_aiida" and "log_check".

> "just check" and "just ci-matrix" are both clean. is that it for aiida?

## Plan

No plan mode. The shape of the session was a loop rather than a plan: the user ran a build
outside the sandbox, redirected it to a log file, named the log, and each turn produced one
root-cause diagnosis, one fix, verification, and a staged commit with a drafted message.

## Out-of-band

Every build in this session was run by the user, in a separate terminal, and handed over as a
log file in the working tree. The sandbox has no nix-daemon, so nothing here can build.

| Log | Command | What it was for |
| --- | --- | --- |
| `log_check` | `just check 2>&1 \| tee log_check` | both eval suites, every VM test, hooks |
| `log_ci` | `just ci-build 2>&1 \| tee log_ci` | one channel's build leg |
| `log_ci_matrix` | `just ci-matrix` | all three channels; stops at the first failure |
| `log_aiida` | a single `nix build -L` of aiida-core | the full 3364-test suite, isolated |
| `log-monty` | likewise for monty | |

These were run in a separate terminal, so only the file names are recoverable from the
transcript, not the invocations or their output. Running them through `!` in the prompt instead
would put both in the record.

## Changes

### QCFractal: a program built for the wrong Python

`183579d` — **`nixos-modules/qcfractal-compute.nix`, `tests/qcarchive/default.nix`.** The VM test
failed with `ImportError: cannot import name 'core' from partially initialized module 'psi4'`,
because the manager ran on 3.13 and Psi4 carried
`core.cpython-314-x86_64-linux-gnu.so`. QCEngine hides this: discovery runs `<program> --module`
as a *subprocess*, which the program's own interpreter answers happily, while compute does an
in-process `import`. So the banner reported `psi4: ['1.11']` and every record then failed.

The old code quietly dropped a mismatched program from `PYTHONPATH`. It now splits "no
interpreter here" from "wrong interpreter" and makes the second an **eval error**, on the
argument that a silently skipped program is worse than a failed evaluation.

`e9ff53e` — **`flake.nix`.** Making the invariant true rather than merely checked: `qchemPkgs`
rewrites `python3` *before* the qchem overlay, so the QC programs are built against the compute
worker's interpreter. The cost is that the resulting Psi4 is not the one
`nix-qchem.cachix.org` holds.

`96202ea` — **cachix.** Which is what motivated this: `nur-berquist` is now the only cache with
that Psi4. Filled in the template's `cachixName` placeholder, dropped `signingKey` (cachix signs
server-side for caches made since 2021, so the auth token is the whole credential), and wired the
consuming half three ways — `nixConfig` for the flake path, the README for the NUR path, and
`system-flake-snippet.nix` for a host. `nix.settings.substituters` concatenates rather than
replaces, because nixpkgs defines `cache.nixos.org` with `mkAfter`, so the snippet adds without
dropping the default.

Also gitignored `/.envrc.local` and `/.env`. `.envrc` is tracked and holds a live push token; it
was never staged, and `git log -S CACHIX_AUTH_TOKEN --all` hits only the template's
`${{ secrets.… }}` text in the initial commit, so history needed no scrubbing.

### AiiDA: eight failures, each hiding the next

`9422bf8` — **`pkgs/aiida-core/default.nix`, `pkgs/plumpy/default.nix`.** The failures only 128
xdist workers can see: per-worker PostgreSQL roles and pinned ports, `TestLaunchersDryRun` and
`test_profile_access` given their own working directories, three tests that assume an empty group
table given `aiida_profile_clean`, and one genuine ordering dependency in
`tests/tools/workflows/test_base.py`.

Plus the plumpy shared-state removal, which is the most reusable thing in this session — see
Outcome.

`3181950` — **`pkgs/pycifrw/**`.** Carried here for the 26.05 leg; the header says when to delete
it again.

`bfb6785` — **`overlays/default.nix`.** `pyprojectVersionPatchHook` does not exist on 26.05, and
naming a missing attribute aborts evaluation of everything downstream. Guarded both mosquito
overrides on `pself ? pyprojectVersionPatchHook` — keyed on the hook rather than on `lib.version`,
because the hook is the attribute that would throw.

`808c740` — **`overlays/default.nix`.** Our own monty patch had rewritten a test to assert
pandas 3's `pandas.DataFrame` spelling; 26.05 has pandas 2.3.3. Gave the assertion the same tuple
the library already got.

`a2f5436` — **`pkgs/aiida-core/default.nix`.** `test_parser_get_outputs_for_parsing` assigns
`ArithmeticAddCalculation.define = CustomCalcJob.define` and never restores it. Visible only when
`_spec` is cold, because `Process.spec()` caches into `cls.__dict__['_spec']` — a cache decides
whether the leak is ever observed. Fixed by warming the cache, then scoping the rebind with
`monkeypatch.setattr`.

`b3fdfd9` — **`pkgs/aiida-core/default.nix`.** click 8.2.2 gave `StreamMixer` a `__del__` that
closes the streams; 8.3.3 removed it. 26.05 carries 8.3.1, both unstable channels 8.3.3, so
`test_list_repository_contents_color` read a closed file on the stable leg only. Moved the read
inside the `with` block, which is correct on every version because `click.echo` flushes.

`1a60ffd` — **`pkgs/aiida-psi4/default.nix`.** aiida-testing keys a recorded result by an md5 of
the working directory, which for the qcschema example includes `input.json` — and that is
`json.dumps` of a qcelemental model, which stamps its own version into two `provenance` blocks.
A diff of the two channels' serialized inputs showed those two strings and nothing else.

`7c8965e` — **`pkgs/aiida-core/default.nix`.** `test_backup`, one run in 128.

## Outcome

`just ci-matrix` and `just check` are both clean. aiida-core sits at **3364 passed**; nine of the
ten plugins pass their own suites.

### What was rejected, and why

**A lock around `Process.spec()`.** A `threading.RLock` was tried first and the failure came
back with it in place: an RLock excludes other *threads* and is transparent to the one already
holding it, so two parties interleaving on a single thread — an asyncio task switch, or a
greenlet, and plumpy depends on both greenback and greenlet — walk straight through. **No lock is
the right answer to shared state reachable without threads.** The state went instead: `spec`
became a local, the flag moved onto the spec object, and `cls._spec` is assigned only once the
spec is complete. Nothing left to race on, under threads, greenlets and asyncio alike.

**`--only-rerun` for anything state-related.** It covers a transient — a lost port, a slow
process. It cannot cover a leaked group row, a deleted repository object or a rebound class
attribute, because the damage outlives the retry and the rerun fails identically. This came up
three separate times.

**`--dist loadfile` for `test_backup`.** Tempting, and backwards: it would put the corrupting
test and its victim in one worker in file order, turning a 1-in-128 failure into a certainty.

**Re-recording the `aiida-psi4` mock digest.** No single digest is right on both channels, since
the digest is a function of the qcelemental version, and any future bump breaks it again. Pinning
the two `provenance.version` strings makes `input.json` byte-identical instead — a no-op on
unstable, so the existing digest was preserved and no re-recording run was needed. Only what
actually differs is pinned: normalizing `routine` as well would have *changed* the digest rather
than preserved it.

**A `builtins.functionArgs` probe to find the missing 26.05 attribute.** Proposed and wrong. It
reads the *signatures* of `pkgs/*/default.nix` and can never see a reference inside an overlay
body, which is where `pyprojectVersionPatchHook` was. It duly returned `{ }`. The check that does
work is an offline `ci-eval` against the channel's own nixpkgs.

### Worth knowing next time

- **The two unstable channels have drifted.** Both report `26.11pre-git`, but they no longer
  resolve to identical derivations — one leg rebuilt aiida-core and pymatgen on its own. Earlier
  notes claiming leg 2 rebuilds nothing are stale.
- **`''` inside a Nix indented string terminates it.** Write `'''` for a literal `''`. `path=''`
  in a search pattern was caught by the nixfmt hook as a syntax error, which is the only reason it
  did not become a pattern-not-found at build time.
- Render `postPatch` and replay it rather than reasoning about the dedent. Doing that caught
  nothing this session precisely because it was done every time.

## Follow-ups

- **`aiida-gaussian` remains unbuildable on both entry points**, and no build fix can change that:
  cclib is still absent from nixpkgs at the locked rev (`f4b6996c`, 2026-08-17), it can only come
  from its own flake, and that flake overrides `python3` alone. Getting it green means cclib
  landing in nixpkgs. `tests/aiida/default.nix` asserts the broken set exactly, so this stays
  visible.
- Python 3.14 is still deferred to its own PR, as the user asked at the top of the session.
- `<YOUR_REPO_NAME>` in `.github/workflows/build.yml` still gates the NUR-update step.
- `log_check` and `log_ci_matrix` are untracked and unignored. Either delete them or add a
  `/log*` line to `.gitignore` — the existing entries are all anchored.

### Proposed, not done

Two commands recurred often enough to be worth making permanent. Neither was added, since the
justfile and `.claude/` are not mine to edit on my own initiative.

- **An offline `ci-eval` against one channel's nixpkgs** — ran about eighteen times, varying only
  the channel. It is the only check that catches a missing-attribute reference *inside* an overlay
  body, which is exactly the class of bug that cost this session two rounds. It is a project
  workflow step, so it belongs in the `Justfile` beside `check-no-daemon` rather than in
  `.claude/`:

  ```
  just eval-channel nixos-26.05
  ```

- **Render-and-replay a `postPatch`** — extract the rendered string with `nix-instantiate --eval`,
  run it against the real source under a `substituteInPlace` shim that fails loudly on a missing
  pattern, then `py_compile` the result. Done four times across `aiida-core` and `aiida-psi4`. It
  has judgement in it — which source path, which files to compile, how to read a
  pattern-not-found — so `.claude/skills/` fits it better than a recipe.
