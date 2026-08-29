---
date: 2026-08-26
slug: wc-packaging-tier-ab
status: partial
sessions: ["4ec8e145-f233-46b2-b67b-553fd1ebc16f"]
touches:
  [
    "pkgs/wignernj/**",
    "pkgs/strainjedi/**",
    "pkgs/sella/**",
    "pkgs/moltui/**",
    "pkgs/chemfiles/**",
    "pkgs/chemfiles-python/**",
    "pkgs/custodian/**",
    "pkgs/fireworks/**",
    "pkgs/dough/**",
    "pkgs/molcat/**",
    "pkgs/metallogen/**",
    "overlays/default.nix",
    "default.nix",
    "flake.nix",
    "tests/chemtools/**",
    "tests/cheminformatics/default.nix",
    "tests/default.nix",
    "scripts/no-daemon-check.sh",
    "Justfile",
    "AGENTS.md",
  ]
---

# Packaging the reachable `wc/` checkouts

Eleven of the twenty-nine unpackaged `wc/` clones, two new overlays, and a new eval suite.
The rest are recorded as deferred with their blockers named, in a new "Deferred packaging"
section of `AGENTS.md`, so the survey does not get redone.

Three of the eleven failed their first real build and were fixed; the fixes are not yet rebuilt,
and the remaining eight are still unbuilt. Status is `partial` for that reason as much as for
the deferrals.

## Ask

Verbatim and in order:

> There are a number of additional repositories under the "wc" directory that need to be
> packaged. Plan that.

> please show the questions again

(after four scoping questions were put through `AskUserQuestion` and the tool call was
rejected — the answer below is to the same questions, restated as plain text)

> 1. A+B first 2. group by family 3. patched pyrr 4. both

(rejecting the first `ExitPlanMode`, with two factual corrections)

> Yes, and use auto mode, but trexio is available in nixpkgs, and ambertools is in nixos-qchem

> /worklog

## Plan

### Context

`wc/` holds 71 upstream clones, gitignored, kept so their `pyproject.toml`, `conftest.py` and
`uv.lock` can be read while packaging. 42 were already packaged under `pkgs/`; **29 were not**.
(`aio-pika` and `aiormq` don't count — they are nixpkgs packages already repaired by the guarded
`mosquito` overrides in `overlays/default.nix`.)

Probing the locked nixpkgs (`nix-instantiate --eval --store dummy://` over `python313Packages`,
`python3.pkgs` and the top level) split the 29 cleanly:

- **13 reachable now** — every dependency in nixpkgs, or needing only cclib plus small helpers.
- **7 gated on one shared prerequisite chain** — `pymatgen-core`, `emmet-core`, `maggma`,
  `mp-pyrho`, `qtoolkit`, `mp-api` all missing, and nixpkgs' `pymatgen` is 2025.10.7 where
  consumers want `>=2026.x`. Unlocks `jobflow`, `jobflow-remote`, `atomate2`, `quacc`, `matgl`,
  `matcalc`, `pymatgen-analysis-defects`. Roughly triples the work.
- **9 out of reach** for reasons that are properties of upstream.

The plan covered the 13, and seeded two new overlays so the deferred chain has a home.

### Scope as agreed

Seventeen derivations for thirteen repos; four extras are dependencies nixpkgs lacks as Python
modules (`pyrr`, `xyzgraph`, `graphrc`, `trexio`).

**New overlay `chemtools`** — standalone tools, no shared closure:

| Package | `wc/` | Pin | Notes |
|---|---|---|---|
| `wignernj` | `libwignernj` | tag `v0.8.0` | C extension via plain setuptools; tests need `sympy` |
| `strainjedi` | `jedi` | `1.1.0-unstable-2026-07-01` | ase, matplotlib, numpy. Not the `jedi` autocompletion library |
| `moltui` | `moltui` | tag `v0.6.1.dev0` | hatchling + hatch-vcs; numpy, scikit-image, textual |
| `trexio` (python) | *(clone)* | 2.6.1 | C library is in nixpkgs, Python module is not |
| `sella` | `sella` | `2.5.0-unstable-2026-07-13` | Cython build; `scipy<1.15` build pin vs nixpkgs 1.18 |
| `chemfiles` | `chemfiles` | tag `0.11.0-rc1` | **Not a Python package** — C++/cmake, top-level |
| `chemfiles-python` | `chemfiles.py` | `0.10.4-unstable-2025-10-16` | external-library and unittest traps |
| `pyrr` | *(clone)* | 0.10.3 + NumPy 2 fixes | carried like `pkgs/pycifrw` |
| `molara` | `Molara` | `0.1.2-unstable-2026-08-17` | PySide6/OpenGL GUI |

**New overlay `materials`** — seeds the deferred chain: `custodian`, `fireworks`.

**Extend `cheminformatics`** (no cclib): `dough` (public leaf), `xyzgraph` (internal).

**Extend `cheminformatics-cclib`**: `molcat`, `metallogen`, `graphrc`, `xyzrender`.

### Traps identified up front

- **`chemfiles-python` runs `unittest`, not pytest.** Test modules are `atom.py`, `cell.py`,
  `frame.py` — matching neither `test_*.py` nor `*_test.py` — so `pytestCheckHook` collects zero
  items and passes. Upstream's tox runs `unittest discover -s tests -p "*.py"`, and the modules
  `import _utils` by bare name.
- **`chemfiles-python` must find the external C++ library.** `find_package(chemfiles CONFIG
  QUIET 0.10)` writes `src/chemfiles/external.py` on a hit and silently falls back to the
  vendored `lib/` submodule on a miss.
- **The `chemfiles` name collides.** A python-set `callPackage` resolves the Python attribute
  first, so a defaulted `chemfiles` argument binds to the binding itself. Thread the library in
  explicitly, as already done for aiida-core's `jq` and postopus's `octopus`.
- **`graphrc` is a dependency that has to be a top-level attribute**, because the cclib split
  forces it. Add it to `cheminformatics-cclib` but do not re-export from `default.nix`.
- **`pyrr` has no source in `wc/`.** nixpkgs removed it outright. Patching Molara off it is not
  viable — some forty call sites use `Vector3`, `Quaternion`, `matrix44`, `vector3`.
- **Molara's suite** needs a display and `pytest-split`, which nixpkgs lacks.
- **CI cost**: `molara` drags PySide6, `sella` drags jax/jaxlib.

### Verification

Sandbox-reachable: `nixfmt` each new file, `just fmt-check`, `just lint`, `just hooks`,
`just check-no-daemon`. User-side: `just build <pkg>`, `just build-flake` for the cclib ones,
the eval suites, then `just ci-eval` / `just ci-build` / `just ci-matrix`.

## Out-of-band

The user ran `just ci-build` (and per-package builds) in a **separate terminal** while the
session was going on, leaving `log_ci_build`, `log-sella`, `log-fireworks` and `log-jedi` in the
working tree, and staging the new files. The commands themselves are not in the transcript and
cannot be recovered — only their output survives, because it was redirected to files in the
repo. Running these through `!` in the prompt is what would have made them recoverable.

Those logs are the only real build evidence this session has, and they were decisive: three of
the eleven packages failed, each for a reason no amount of evaluation would have surfaced. See
Outcome.

The two factual corrections (`trexio`, `ambertools`) came as prose and were verified from inside
the sandbox against the locked nixpkgs and the `nixos-qchem` flake input already in the store.

## Changes

Eleven new packages, two new overlays, one new eval suite. Nothing was built — the sandbox has
no daemon — so every claim below is eval-level.

**New packages**

| File | Why |
|---|---|
| `pkgs/wignernj/default.nix` | `preCheck` deletes the shadowing source dir: the suite `pytest.skip`s itself at module level if `import wignernj` fails, and from the source root it would import the extension-less directory and skip everything silently |
| `pkgs/strainjedi/default.nix` | MIT, not GPL — checked the LICENSE rather than trusting the repo name |
| `pkgs/moltui/default.nix` | `buildPythonApplication`; trexio extra left off with the `importorskip` reasoning recorded |
| `pkgs/sella/default.nix` | `SETUPTOOLS_SCM_PRETEND_VERSION` derived from `version` via `lib.head (lib.splitString "-" version)`; upstream's `fallback_version = "0.0.0"` would otherwise install silently wrong |
| `pkgs/chemfiles/default.nix` | C++ library, `BUILD_SHARED_LIBS` forced on (the binding fatals on a static one), system zlib/xz/bzip2 |
| `pkgs/chemfiles-python/default.nix` | No `fetchSubmodules`; `postInstall` asserts `external.py` exists *and* names our store path; `checkPhase` mirrors upstream's `unittest discover` |
| `pkgs/custodian/default.nix` | pymatgen as a check input — 7 of 21 test modules import it |
| `pkgs/fireworks/default.nix` | `mainProgram = "lpad"`; no MongoDB needed, reasoning recorded |
| `pkgs/dough/default.nix` | hatch reads the version from `__about__.py`, so no scm hole |
| `pkgs/metallogen/default.nix` | `doCheck = false` with the reason: `MetalloGen/test.py` is the main module, not a suite |
| `pkgs/molcat/default.nix` | `unfree` (no licence at all) and `pythonImportsCheck = [ "src" ]` (top-level `src` module) |

**Wiring**

- `overlays/default.nix` — hoisted the aiida overlay's pymatgen override into a file-level
  `pymatgenFor` binding; added `chemtools` and `materials`; added `dough` to `cheminformatics`
  and `molcat`/`metallogen` to `cheminformatics-cclib`.
- `default.nix` — re-exported the public leaves; `chemfiles` (C++) via `inherit (pkgs')`,
  `moltui` alongside `dotdrop`/`harmonwig`.
- `flake.nix` — `metallogen` added to the `cclibPkgs` override block, `molcat` deliberately not.
- `tests/chemtools/default.nix` — new, 8 assertions.
- `tests/cheminformatics/default.nix` — `dough` into `exportedPackages`, `molcat`/`metallogen`
  into `cclibPackages`.
- `tests/default.nix`, `Justfile`, `scripts/no-daemon-check.sh`, `AGENTS.md` — dispatch, recipe,
  check coverage, and sixteen new rows in "Where the explanations live" plus the new
  "Deferred packaging" section.

No commits made.

## Outcome

`just check-no-daemon` green: 36 qcarchive, 34 aiida, 6 cheminformatics, 8 chemtools, every VM
test instantiates, 78 files parse. `shellcheck` clean on the modified script.

### Three real build failures, from the user's out-of-band logs

Every one of these passed evaluation and would have been reported as "written, not built" had
the logs not been in the tree. This is the argument for the build loop, in three examples.

**`sella` — `pythonRelaxDeps` cannot relax a build-system requirement.**

```
ERROR Unmet dependencies (checked against .../bin/python3.13):
 scipy<1.15,>=1.1.0     wanted: <1.15,>=1.1.0   found: 1.18.0
 setuptools<82,>=74.1.0 wanted: <82,>=74.1.0    found: 83.0.0
```

`pythonRelaxDeps` rewrites the *runtime* Requires-Dist of the built wheel. What fails here is
the build-dependency check against `[build-system] requires`, run before the backend is loaded
— a different table that the hook never touches. Replaced with a `postPatch` that edits both
caps in `pyproject.toml`. The `setuptools<82` cap was not even noticed when the package was
written; only the build reported it.

**`strainjedi` — upstream ships a package list that omits a subpackage it imports.**

```
File ".../strainjedi/jedi.py", line 12, in <module>
  from strainjedi.visualization import ColorMapper, MatplotlibVisualizer, VMDVisualizer
ModuleNotFoundError: No module named 'strainjedi.visualization'
```

`[tool.setuptools] packages` names `strainjedi` and `strainjedi.io` but not
`strainjedi.visualization`, and setuptools does not recurse when the list is explicit. So the
wheel is missing a subpackage that `__init__.py` transitively imports — the installed package
cannot be imported at all. An editable install off a git checkout hides this, which is
presumably how it survives upstream. Fixed by adding the entry in `postPatch`; also set `HOME`
in `preBuild`, since matplotlib was falling back from `/homeless-shelter`.

**`fireworks` — wrong version, and `monty` needs a numpy it does not declare.**

```
File ".../monty/json.py", line 24, in <module>
  import numpy as np
ModuleNotFoundError: No module named 'numpy'
```

Two independent problems. The build log's `Successfully built fireworks-2.1.4-py3-none-any.whl`
contradicted the declared `2.0.2`: `git describe` reports the v2.0.2 tag for this commit, but
setup.py says `version="2.1.4"`, and atomate2/jobflow both pin `FireWorks==2.1.4`. Same
tag-behind-source trap already hit on `chemfiles.py`. Separately, `monty/json.py` imports numpy
unconditionally while nixpkgs lists numpy only in monty's `optional-dependencies` — a latent
nixpkgs bug that every monty dependant reaching serialization will hit. Added numpy to
fireworks rather than repairing monty in the overlay, which would change it for every consumer.

All three fixes are eval-clean but **not yet rebuilt** — they need another `just ci-build`.

### Verifying the rendered patches rather than trusting them

Both new `postPatch` blocks were extracted with `nix-instantiate --eval --raw` and run against
real copies of the upstream `pyproject.toml` under a `substituteInPlace` stand-in, then the
result parsed with `tomllib`. This caught that `''` dedents to the *minimum* indentation across
the block, so the continuation line of the strainjedi replacement rendered at column 0; it needs
8 spaces in the file to emerge as 4. Valid TOML either way, but the check is what turned a guess
into a fact.

### What the eval tests caught that review would not have

**`moltui` in a Python package set is an eval error, not a style slip.** It is a
`buildPythonApplication`, and nixpkgs rejects a non-module in a package set with *"moltui should
use `buildPythonPackage` or `toPythonModule`"*. This took the whole `chemtools` overlay down on
first instantiation. Moved to a top-level attribute beside `dotdrop` and `harmonwig`, and
`tests/chemtools` now asserts the shape with an `applicationPackages` list.

**`chemtools-python-pin` failed for a reason that had nothing to do with the pin.** The test
compared a partial overlay composition against `default.nix`'s full one, and `custodian` and
`fireworks` differed — because the **aiida overlay patches `monty`** (a pandas 3 fix) in the
package set, and both depend on it. Added a `fullyOverlaidPkgs` binding and documented that
`tests/cheminformatics` gets away with a partial composition only by coincidence, not by design.

### Rejected approaches

- **Patching Molara off `pyrr`** — rejected after counting the call sites: `Vector3`,
  `Quaternion`, `matrix44` and `vector3` across `rendering/camera.py` and
  `tools/raycasting.pyx`. That is a fork, not a patch. Carrying a patched `pyrr` is the plan.
- **Duplicating the pymatgen override into the `materials` overlay** — rejected. Fifty lines of
  deselection rationale in two places would drift silently, and the drift would only surface
  when one of them broke. Hoisted to a shared `pymatgenFor` function instead, still a `let`
  binding so it never enters a consumer's package set; `materials-pymatgen-override-is-local`
  asserts that, mirroring the existing aiida test.
- **Aliasing the Python `chemfiles` binding at the top level** — rejected. One name cannot be
  both the shared library and the module. `pkgs.chemfiles` is the library (as every other
  distribution spells it) and `python313Packages.chemfiles` is the module (as pip spells it).
- **Putting `molcat` in the flake's `packages`** — rejected. `nix flake check` forces every
  attribute there, and molcat is `unfree`, so nixpkgs would refuse to evaluate it and take the
  whole check down. It stays reachable through `legacyPackages`.
- **Enabling the chemfiles C++ suite** — deferred, not skipped. `tests/CMakeLists.txt` does a
  `file(DOWNLOAD ...)` of `chemfiles/tests-data` at *configure* time, so it fails at cmake, not
  ctest. The fix is to supply the data as a second `fetchFromGitHub` and touch the marker file
  the `if(NOT EXISTS ...)` guard checks — one clone away, documented at the code.

### Corrections taken from the user

Both were right and both changed the plan:

- **`trexio` is in nixpkgs** — as `pkgs/by-name/tr/trexio` 2.6.1, but it is the *C library*: a
  `stdenv.mkDerivation` listing `python3` and `swig` as native inputs for code generation, with
  no importable module in any package set. So moltui's extra is cheap to enable once the thin
  swig wrapper is packaged, rather than being unavailable.
- **`ambertools` is in nixos-qchem** — at `pkgs/python-by-name/ambertools`, a Python package.
  That removes the hard blocker from the OpenFF chain, though nixos-qchem carries no `openff-*`,
  so the seven wrapper packages remain. Being a flake input puts it under the cclib constraint.

### Not done

`xyzgraph`, `graphrc`, `xyzrender`, `pyrr`/`molara`, and the `trexio` binding are all blocked on
sources not in `wc/` and unreachable from the sandbox (no network). `xyzgraph` and `graphrc` are
PyPI-only; their sdist hashes are already recoverable offline from `wc/xyzrender/uv.lock` via
`nix hash convert`, but the build backend and whether the sdists ship tests cannot be known
without the source.

One hash is a best guess: `chemfiles.py` has a git submodule at `lib/`, and `git archive` leaves
an empty directory where GitHub's tarball omits the path entirely, so it was removed before
hashing. A mismatch on first build is self-correcting — Nix prints the right value.

## Follow-ups

- Clones needed to finish the agreed scope:
  ```sh
  git clone --depth 1 https://github.com/adamlwgriffiths/Pyrr wc/pyrr
  git clone --depth 1 --branch v2.6.1 https://github.com/TREX-CoE/trexio wc/trexio
  git clone --depth 1 https://github.com/chemfiles/tests-data wc/chemfiles-tests-data
  git clone --depth 1 https://github.com/aligfellow/xyzgraph wc/xyzgraph
  git clone --depth 1 https://github.com/aligfellow/graphrc wc/graphrc
  ```
  The last two URLs are inferred from xyzrender's authorship and need confirming.
- Re-run `just ci-build`. Three packages were fixed after the logs came in (`sella`,
  `strainjedi`, `fireworks`) and none of the fixes has been built. The other eight had not been
  reached before the run aborted, so they are still unverified: `wignernj`, `moltui`, `dough`,
  `custodian`, `chemfiles`, `chemfiles-python`, `metallogen`, `molcat`.
- `just fmt-check`, `just lint`, `just hooks` — none has been run; `nixfmt`, `statix` and `prek`
  are devShell-only and the sandbox cannot enter it.
- **Decide what to do about `molcat`.** No licence at all, and it installs a top-level `src`
  module into any environment that includes it. Packaged with both documented, but dropping it
  is defensible.
- **Proposed recipe — `just eval-probe '<expr>'`.** The preamble
  ```sh
  export XDG_CACHE_HOME="$TMPDIR/nix-cache"
  export NIXPKGS_CONFIG=
  narhash=$(jq -r '.nodes.nixpkgs.locked.narHash' flake.lock)
  nixpkgs=$(nix-store --print-fixed-path --recursive sha256 \
      "$(nix-hash --to-base16 --type sha256 "${narhash#sha256-}")" source)
  export NIX_PATH="nixpkgs=$nixpkgs"
  nix-instantiate --eval --strict --json --store dummy:// --expr "$1"
  ```
  (as written above it passes `shellcheck --shell=bash --exclude=SC2148` and `shfmt` under the
  repo's `.editorconfig`; the one-line `export NIX_PATH="$(...)"` spelling actually used during
  the session trips SC2155)
  was retyped some fifteen times this session, to answer "is X in nixpkgs and at what version".
  `scripts/no-daemon-check.sh` already encapsulates it for the *fixed* suite of checks but
  offers no way to run an ad-hoc expression. This is a stable workflow step — every packaging
  session starts with it — so it belongs in the Justfile, wrapping a `scripts/eval-probe.sh`.
- **Proposed script — `scripts/offline-src-hash.sh <wc-dir> <rev>`.** `git archive <rev> | tar x`
  into a scratch dir then `nix hash path` is how a `fetchFromGitHub` hash is obtained without
  network or daemon. Two gotchas are worth encoding rather than rediscovering: a submodule path
  must be removed (GitHub's tarball omits it, `git archive` leaves an empty dir), and
  `.gitattributes` `export-ignore` entries must be checked. Currently only a memory note.
