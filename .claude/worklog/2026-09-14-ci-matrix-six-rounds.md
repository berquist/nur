---
date: 2026-09-14
slug: ci-matrix-six-rounds
status: done
sessions: ["daeb0e3e-f9c2-462a-8a2f-d8079e918695"]
touches:
  - "pkgs/rootstock/**"
  - "pkgs/torch-pme/**"
  - "pkgs/colour-science/**"
  - "pkgs/nvalchemi-toolkit-ops/**"
  - "pkgs/deepmd-kit/**"
  - "pkgs/matcalc/**"
  - "pkgs/aiida-core/**"
  - "overlays/default.nix"
  - "scripts/channel-gaps.sh"
  - "scripts/channel-gaps.nix"
  - "Justfile"
---

# Six rounds of `log_ci_matrix`, and a tool for the round that keeps repeating

## Ask

Eight prompts, verbatim and in order.  Six of them are the same two words.

> read "log_ci_matrix"

> 1. I updated the rootstock repo clone in "wc".  2. don't deselect; patch.  3. we should repackage
> openimageio  4. yes, deselect network, yes, investigate digest

> read "log_ci_matrix"

> make all four changes

> read "log_ci_matrix"

> read "log_ci_matrix"

> 1. yes, write it up as a just recipe  2. read "log_ci_matrix"

> read "log_ci_matrix"

> yes, write the worklog

## Plan

None.  Plan mode was never entered; the shape of the session was a loop — read the log, diagnose,
propose, wait for direction, fix, hand back — and the direction arrived in prompts 2, 4 and 7
rather than in an approved plan.  That turned out to matter twice: prompt 2's "don't deselect;
patch" reversed what would otherwise have been a `disabledTests` entry on `torch-pme`, and prompt 7
asked for tooling that six rounds had by then justified.

## Out-of-band

Every round began with the user running the matrix in a separate terminal and redirecting the
output:

```sh
cachix watch-exec nur-berquist -- just push-matrix   # > log_ci_matrix
```

The command is recoverable only because the log's own first line records it — a separate terminal
leaves nothing in the transcript.  `!` in the prompt is what would have made it recoverable
properly, and is worth using for the next long-running run.

The user committed between rounds; each round's message was drafted to `.git/round<N>-commit-msg.txt`
and printed rather than committed.

## Changes

Six commits, one per round.

| Commit | What |
|---|---|
| `85ed5fd` | rootstock's owner, torch-pme's tolerance patch, openimageio retargeted at python313, colour-science's xxhash/openimageio/`av` and the network deselect |
| `86a9992` | colour-science `av` → `opencv4`; nvalchemi's `prefactor` patch, 28 CUDA literals and the vesin dtype fix |
| `4d35284` | rootstock's `dontBypassUvDynamicVersioning`, nvalchemi's two-device skip, colour-science's single-channel EXR patch |
| `d84c17a` | `sevenn`, `tensorpotential` and `deepmd-kit` gated for nixos-26.05's missing `e3nn` / `matscipy` |
| `204b010` | nvalchemi's warp-lang *version* gate, aiida-core's 120-second budget, and `just channel-gaps` |
| `f044422` | `deepmd-kit` gated on `scikit-build-core >= 1` |

New files: `pkgs/torch-pme/combined-potential-tolerance.patch`,
`pkgs/nvalchemi-toolkit-ops/torchpme-prefactor-moved.patch`,
`pkgs/colour-science/imageio-single-channel-exr.patch`, `scripts/channel-gaps.sh`,
`scripts/channel-gaps.nix`.  Fourteen rows added to AGENTS.md's explanations table.

## Outcome

The matrix went from failing its first leg to failing only the third, and the failure count fell
every round: 4 derivations → 3 → 3 → an eval abort → 2 → 1 → 0 pending.  Both unstable legs build
clean.  Test suites that had never run now do: `nvalchemi-toolkit-ops` reports 4086 passed / 2160
skipped where its first complete run was 103 failures, and `colour-science` 2610 passed where it
was 17 failures.

### What the six rounds actually were

Round 1 fixed four unrelated things and **each fix revealed the next layer**, which is the pattern
AGENTS.md already records for the sdist trap:

* `torch-pme` was a check input of `nvalchemi-toolkit-ops`, so fixing torch-pme let nvalchemi's
  suite run for the first time — 103 failures that had been invisible behind a dependency failure.
* `rootstock`'s 404 was a repo that had moved owner; fixing that produced a 504; fixing *that*
  produced a hatchling failure that had been sitting behind the fetch all along.
* nixos-26.05 was never reached until leg 1 passed, and then produced an eval abort, which by its
  nature reports one offender when there were three.

### Rejected, and why

* **`torch-pme`: seeding the RNG.**  `test_combined_potential` draws unseeded `torch.randn`
  weights, so the obvious fix is a seed.  Rejected: it fixes the one draw that failed and leaves
  the next.  The tolerance is scaled from the same draw instead, which holds for all of them.
* **`torch-pme`: deselecting.**  Ruled out by prompt 2, and rightly — the failure was correct
  rounding against an `atol` below one ulp of the operands.
* **`colour-science`: `av` as the EXR backend.**  Tried and shipped in round 1, wrong.  imageio
  *does* select pyav, and ffmpeg's EXR decoder then fails inside `avcodec_send_packet()`.
* **`colour-science`: keeping `av` beside `opencv4`.**  imageio consults its priority list once, at
  plugin selection; the pyav failure comes later, at read time, with no fall-through.  `av` had to
  leave, not be joined.
* **`colour-science`: FreeImage, the backend upstream develops against.**  imageio will load a
  system copy via `IMAGEIO_FREEIMAGE_LIB` rather than downloading, so this looked promising.
  It is impossible: nixpkgs **removed** `freeimage` — `error: freeimage was removed due to numerous
  vulnerabilities`.  Permanently unavailable, not merely absent.
* **`colour-science`: deselecting `test_read_image_Imageio`.**  Would have thrown away three
  assertions that pass.  The patch removes two lines instead, and the same
  `Single_Channel.exr` → `(256, 256)` assertion still runs in `TestReadImage` through OpenImageIO.
* **`openimageio`: adding nixpkgs' attribute as a check input.**  A no-op.  nixpkgs already builds
  the binding (`enablePython` defaults true) but against `python3Packages.pybind11`, and `python3`
  is 3.14 on these channels, so it installs where no 3.13 set will look.
* **nvalchemi `test_device_mismatch`: `disabledTests`.**  It needs *two distinct devices*, not a
  CUDA one — it pairs the module's device constant against a hard-coded `"cpu"`.  That is the CUDA
  gate's business, and a skip with a reason beats a silent drop.
* **`deepmd-kit`: relaxing `minimum-version`, or backporting scikit-build-core.**  The first is
  scikit-build-core's compatibility-policy knob rather than a floor to argue with; the second is a
  monty-style backport of a build backend most of nixpkgs' Python tree uses.
* **`channel-gaps`: comparing `functionArgs` against the channel.**  This is what found the three
  26.05 gaps by hand in round 4, and it is wrong in both directions — it calls
  `chemfiles-python`'s `chemfilesLib` and `molara`'s `mesaDrivers` gaps when the overlay passes
  both explicitly, and it sees nothing of a failure that is not a missing argument.  The script
  forces each attribute in its own process instead.

### One thing got fixed wrong and had to be corrected

Round 4 left `matcalc`'s `deepmd` extra unconditional, on the reasoning that `deepmd-kit` wants
`e3nn` for an extra of its own rather than as a dependency and so survives 26.05.  True about
`e3nn`, and wrong about the channel: round 6 found it fails there on `scikit-build-core` instead.
The lesson is in the note now — "survives this channel" is a claim about the whole package, not
about the one dependency being reasoned over.

### Traps found along the way

* **`scripts/offline-src-hash.sh` gives a wrong hash for a subdirectory of a clone.**  It passes
  the argument to `git -C` but `git archive` defaults to the *current working directory* as a path
  restriction, so pointing it at `wc/rootstock/rootstock` silently hashes that subtree.  Two
  different hashes, no warning.  See Follow-ups.
* **nixpkgs' `uv-dynamic-versioning` ships a setup hook** that exports
  `UV_DYNAMIC_VERSIONING_BYPASS` from `$version` in `preBuildHooks`, which runs after `env` and
  wins.  A derivation's own `env.UV_DYNAMIC_VERSIONING_BYPASS` is dead code without
  `dontBypassUvDynamicVersioning = true`, and only a non-PEP-440 version reveals it.
* **A non-Python derivation in a Python package set needs `toPythonModule`**, and the guard is
  lazy enough to be inconsistent: `pself.openimageio.out` slipped past it while
  `python313Packages.openimageio` threw.
* **`nix-instantiate --eval file.nix` prints `<LAMBDA>`** unless given at least one `--arg`, even
  when every argument has a default.
* **Three shapes of channel gate, not one.**  A missing name aborts at eval; a runtime dependency
  that is too old fails at `pythonRuntimeDepsCheckHook` after the wheel is built; a build backend
  that is too old fails before the backend is even asked what the build requires.  Only the first
  is findable without building.

## Follow-ups

* **`scripts/offline-src-hash.sh` should resolve its argument to the repository toplevel.**  One
  line — `git -C "$clone" rev-parse --show-toplevel` — turns a silently wrong hash into a correct
  one.  Worth doing before the next `-unstable-` bump.
* **Sandbox PATH for the formatter/linter set.**  `nixfmt` ran 66 times this session, `shellcheck`
  34, `statix` 33, `shfmt` 18, `prek` 18 — and every one needed a store path hunted out by hand,
  because `just fmt` / `just lint` / `just hooks` all fail inside the sandbox with
  `command not found`.  `scripts/sandbox-path.sh` already solves this for `ls`, `git` and `nix`;
  extending it to the devshell's formatters would remove roughly 150 store-path lookups per session
  of this shape.  A proposal, not a change — it touches shared tooling.
* **`aiida-core`'s 120-second budget is reasoned, not measured.**  If
  `test_restart_after_daemon_reset` times out again, the number is not the problem: a process that
  will not leave WAITING two minutes after a daemon restart is worth treating as a real defect.
* **`nvalchemi-toolkit-ops` skips 2160 tests**, nearly all of them the CUDA gate.  Nobody has seen
  what they do on a machine with a GPU.
* **`just channel-gaps` cannot see a version floor**, and 26.05 has now supplied two.  Its header
  says so with both worked examples.  Chasing them properly would mean parsing PEP 508 metadata
  *and* `[tool.scikit-build] minimum-version`, neither knowable without building — probably not
  worth it, but the third instance would be the moment to reconsider.
