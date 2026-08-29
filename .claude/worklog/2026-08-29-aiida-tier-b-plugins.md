---
date: 2026-08-29
slug: aiida-tier-b-plugins
status: partial
sessions: ["fee26b1d-5489-49d9-b81c-ab6653216bf3"]
touches:
  - "pkgs/aiida-ase/**"
  - "pkgs/aiida-gromacs/**"
  - "pkgs/aiida-lammps/**"
  - "pkgs/aiida-nwchem/**"
  - "pkgs/aiida-optimize/**"
  - "pkgs/aiida-shell/**"
  - "pkgs/aiida-submission-controller/**"
  - "pkgs/aiida-wannier90/**"
  - "pkgs/sisl/**"
  - "pkgs/fireworks/**"
  - "overlays/default.nix"
  - "default.nix"
  - "tests/aiida/default.nix"
  - "scripts/offline-src-hash.sh"
  - "Justfile"
  - "AGENTS.md"
  - ".scratch/nixpkgs-plumed-mpi.patch"
---

# AiiDA tier B: seven plugins, and five layers of NWChem

## Ask

1. I'm trying to rebase this branch on top of "origin/main".  Can you look at "overlays/default.nix" and figure out how to solve the conflict?
2. read "log-fireworks"
3. I am not mid rebase, it's done; apply the fixes
4. Continue with the plan you were working on.  I think it's the one in the ".scratch/" directory.
5. read all of the files in the current working directory that are have filenames starting with "log"
6. read "log-gromacs", "log-nwchem", and "log-lammps"
7. read "log-nwchem" and "log-gromacs"
8. read "log-probe-nwchem" and "log-probe-gromacs"
9. doesn't the gromacs/plumed segfault during testing mean that the same thing will happen during normal runs?  is forcing serial execution in the test just hiding the real problem?
10. read "log-probe-gromacs" again
11. draft the nixpkgs plumed MPI patch and make any necessary fixes here, then reread "log-nwchem"
12. reread "log-probe-nwchem".  I cloned a copy of nwchem under "wc".  I think you want to search for files that include the string "system crystal", particularly documentation.
13. I've cloned a copy of plumed into 'wc/plumed2'.  Read 'user-doc/Installation.md' as a start for how to set the correct flags.  you can also read the github workflows for more information.  also reread 'log-nwchem'
14. read "log-probe-nwchem" again
15. reread 'log-nwchem'
16. "just ci-matrix" and "just check" are both passing
17. write the worklog

Prompts 5–15 are the shape of the session: the user rebuilt out of band and handed back a log,
over and over. That loop is the method, not an accident — see Outcome.

## Plan

Tier B of the plan below, plus the two tier-A dependencies that needed no network. Tier C and
the rest of tier A were not reached; the Follow-ups say what blocks each. The plan was written
in an earlier session and lives at `.scratch/aiida-new-packages-plan.md`, which is untracked, so
it is inlined here in full.

---

## Add the sixteen new AiiDA plugins

> Copy of the approved plan, kept in the repo (bind-mounted, survives a sandbox
> restart) because `~/.claude/plans/` may sit on the ephemeral tmpfs.
> Original: `~/.claude/plans/read-the-previous-worklog-scalable-glade.md`.
>
> **State when the sandbox died:** plan approved, **no repo files changed yet**.
> Nothing is half-applied. The four missing clones have since landed in `wc/aiida/`.
> Resume at "Before starting".

### Context

`.claude/worklog/2026-08-26-pollution-lottery.md` closes with a follow-up naming this session:

> **Session after that — the new packages.** Fifteen clones are already under `wc/aiida/` …
> Order by leverage: `aiida-shell` first — aiida-core's own docs name it more than any other
> plugin, its footprint is essentially aiida-core alone, and it turns the ~60 programs already
> reachable through `pkgs.qchem.*` into things AiiDA can drive without a plugin each. Expect the
> sdist-has-no-tests trap on every one of these; see `AGENTS.md`.

The prerequisite it named first — the `origin/main` divergence — is already resolved: `439102c`
merged the aiida branch and `14c55a7` carried the `nixpkgs-qchem` digest bump.

`wc/aiida/` held **sixteen** clones (the worklog undercounted by one), and now holds **twenty**:
the four dependency projects this plan needs have since been cloned there too. This plan packages
all of them plus the two remaining dependency packages, taking the AiiDA family from seven plugins
to twenty-one.

### What is being added

Twenty-two new derivations. Dependency order is the build order.

#### Tier A — dependencies nixpkgs does not carry

| Package | Source | Notes |
|---|---|---|
| `node-graph-widget-js` | `wc/aiida/node-graph-widget` | `buildNpmPackage`, esbuild bundle |
| `node-graph-widget` | same clone | hatchling + `anywidget` |
| `node-graph` | `wc/aiida/node-graph` | flit-core; 35 test modules |
| `starlette-graphene3` | `wc/aiida/starlette-graphene3` | pure Python, for `aiida-restapi` |
| `pyfirecrest` | `wc/aiida/pyfirecrest` | pure Python, for `aiida-firecrest` |
| `sisl` | `wc/aiida/sisl` | scikit-build-core + meson + Cython + Fortran |
| `aiida-optimize` | `wc/aiida/aiida-optimize` | for `aiida_siesta_plugin` |

All twenty sources are local, so nothing here is blocked on the network.

#### Tier B — plugins whose every dependency already resolves

`aiida-shell`, `aiida-submission-controller`, `aiida-wannier90`, `aiida-ase`, `aiida-nwchem`,
`aiida-gromacs`, `aiida-lammps`.

#### Tier C — plugins that depend on tier A or B

`aiida-pythonjob`, `aiida-phonopy`, `aiida-workgraph`, `aiida-wannier90-workflows`,
`aiida-restapi`, `aiida-firecrest`, `aiida-siesta`.

Verified present in the locked nixpkgs (`python313Packages`), so nothing else has to be packaged:
`anywidget` 0.9.21, `ase` 3.29, `dill` 0.4.1, `phonopy` 4.4.0, `seekpath` 2.2.1, `voluptuous`
0.16.0, `graphene` 3.4.3, `lark` 1.3.1, `fastapi` 0.139, `uvicorn` 0.51, `python-multipart` 0.0.32,
`rdflib`, `graphviz`, `wrapt`, `cloudpickle`, `jsonschema` 4.26, `hatch-jupyter-builder`. Simulation
binaries too: `lammps`, `gromacs`, `nwchem`, `wannier90`, `siesta`, `quantum-espresso`, `nodejs`.
`gpaw` is there as well — it is a Python package, not a top-level attribute, which is why a
`pkgs.gpaw` probe reported it missing; reach it through the package set.

### Before starting

`starlette-graphene3`, `pyfirecrest`, `sisl` and `aiida-optimize` have been cloned into
**`wc/aiida/`** alongside the other sixteen, not into `wc/`. Read their `pyproject.toml` /
`setup.py` first — their dependency lists are the one part of this plan not yet verified against a
real source tree, and `sisl`'s build system in particular is only assumed.

Note that these four were cloned with `--depth 1`, so `git describe` and `git log` see one commit
and no tags. Version the derivations from the project metadata rather than from a tag, or ask for
an unshallow.

Every source is local, so every `fetchFromGitHub` hash in tiers A–C can be computed without the
network, per the `offline-fetchfromgithub-hashes` memory:

```sh
git -C wc/aiida/<pkg> archive --format=tar <rev> | (mkdir -p "$t" && tar -x -C "$t")
nix hash path "$t"
```

### Implementation

#### The per-package derivation

Each `pkgs/<name>/default.nix` follows `pkgs/aiida-cp2k/default.nix` and
`pkgs/aiida-orca/default.nix`, which between them already show every mechanism these sixteen need:

- **`src = fetchFromGitHub`, never `fetchPypi`.** Every one of these projects excludes `tests/`
  from its sdist (flit's `[tool.flit.sdist] exclude`, or hatch shipping wheels only). See the
  sdist-has-no-tests trap in `AGENTS.md`: the failure is silent, so **confirm the collected count
  is non-zero before believing a green build**. Take the tag when the clone sits on one; otherwise
  the repo's `X.Y.Z-unstable-YYYY-MM-DD` + `rev` scheme, as `aiida-orca` does.
- **`pythonRelaxDeps = [ "aiida-core" ]` on every plugin.** Our aiida-core is `2.10.0.dev0`, and a
  pre-release does not satisfy `aiida-core~=2.x` under PEP 440. `pkgs/aiida-orca/default.nix`
  carries the comment to point at.
- **`preBuild`**, not `preCheck`, for `HOME` and `AIIDA_PATH` — reason is in
  `pkgs/aiida-core/default.nix`.
- **`preCheck`** exporting `LOCALE_ARCHIVE` from `glibcLocalesUtf8` on Linux for any suite that
  builds a PostgreSQL profile — see `pkgs/pgsu/default.nix` for why the locale is supplied rather
  than the constant rewritten.
- **`pgtest` + `postgresql`** in `nativeCheckInputs` wherever `conftest.py` names
  `aiida.manage.tests.pytest_fixtures` or `aiida.tools.pytest_fixtures` — which is all of
  `aiida-shell`, `aiida-restapi`, `aiida-wannier90`, `aiida-nwchem`, `aiida-gromacs`,
  `aiida-firecrest`, `aiida-pythonjob`, `aiida-ase`.
- **`procps`** wherever a test actually submits through the `direct` scheduler; without `ps` the
  joblist comes back empty and the parser reads a half-written file. `pkgs/aiida-cp2k` and
  `pkgs/aiida-octopus` both document the shape the failure takes.
- **`disabledTestPaths` as a canary.** A glob that matches nothing aborts the build, which is the
  cheapest available proof that the suite ran at all.

#### Package-specific work, in build order

**`node-graph-widget-js`** — `buildNpmPackage` over `wc/aiida/node-graph-widget`.
`npmBuildScript = "build"`; the esbuild output lands in `src/node_graph_widget/static/`, so
`installPhase` copies that directory to `$out`. Two things to watch: `package-lock.json` is
`lockfileVersion: 2` and its root `""` entry declares no `name`/`version`, which some `npm ci`
paths object to — patch the lockfile root in `postPatch` if it does. `npmDepsHash` needs one
build to discover.

**`node-graph-widget`** — hatchling. `preBuild` copies the tier-A bundle into
`src/node_graph_widget/static/`; that satisfies
`[tool.hatch.build.hooks.jupyter-builder] skip-if-exists`, so the npm hook becomes a no-op and no
network is needed at Python build time. `dependencies = [ anywidget ]`. Its one test needs
playwright — leave it uncollected and rely on `pythonImportsCheck`.

**`node-graph`** — flit-core. Deps: `numpy scipy cloudpickle node-graph-widget wrapt pydantic
typing-extensions pyyaml rdflib graphviz click`. `node_graph/task.py` imports `node_graph_widget`
at module scope, so the widget is a hard runtime dependency, not an extra.

**`aiida-shell`** — the highest-leverage one and the smallest: `flit-core`, deps `aiida-core` and
`dill`. `tests/data/test_code.py` hardcodes `filepath_executable='/bin/bash'`, which a build sandbox
does not have; `substituteInPlace` it to `${bash}/bin/bash` exactly as `pkgs/aiida-orca` does.
`tests/test_launch.py` resolves `date`/`echo`/`cat`/`head`/`tar` through `shutil.which`, so
coreutils and gnutar on the check PATH is enough.

**`aiida-submission-controller`** — `flit-core`, deps `aiida-core pydantic rich`. Ships **no tests
at all**, so `pythonImportsCheck` is the whole check. Trivial; do it second to bank a quick win.

**`aiida-wannier90`** — `flit-core`, only dependency is `aiida-core`. Tests name the *deprecated*
fixture plugin (`aiida.manage.tests.pytest_fixtures`); `pkgs/aiida-core/default.nix` documents what
that module needs patched and why both fixture modules get the per-worker role and port fixes.

**`aiida-ase`** — `flit-core`, deps `aiida-core ase`. `tests/conftest.py` uses `/bin/true`, which is
resolvable. The gpaw parser tests replay stored output, but nixpkgs *does* carry `gpaw` in the
Python set, so put it in `nativeCheckInputs` and let the suite exercise the real parser rather than
assuming replay is all that is on offer.

**`aiida-nwchem`** — `flit-core`, deps `aiida-core[atomic_tools] numpy`. The extra is not enforced
by the dependency check, but the suite wants it: add `ase pymatgen seekpath spglib` as check inputs.
`conftest.py` calls `aiida_local_code_factory(executable='nwchem')`, so `nwchem` goes in
`nativeCheckInputs`. Thread `pymatgen` in from the overlay's local binding, the way
`overlays/default.nix` already does for `aiida-core` and `aiida-gaussian`.

**`aiida-gromacs`** — `flit_core >=4,<5`; check the locked `flit-core` is 3.12 and relax or supply
accordingly. Pins `aiida-core>=2.8.0,<=2.8.1` — an upper bound, so `pythonRelaxDeps` is mandatory,
not cosmetic. `voluptuous==0.16.0` matches nixpkgs exactly. `conftest.py` wants `gmx` and `bash`;
`gromacs` into `nativeCheckInputs`. Nine console scripts, so pick `meta.mainProgram` deliberately
(`genericMD` is the general one).

**`aiida-lammps`** — `flit-core`, deps `aiida-core[atomic_tools] importlib-resources jsonschema
numpy packaging python-dateutil`. **`jsonschema~=3.2.0` against nixpkgs' 4.26 is the real risk
here**, not just a relax: jsonschema 4 removed `RefResolver` and changed validator construction.
Relax first, then read the failure — if `aiida_lammps/validation/` uses the removed API, patch the
call site rather than pinning an old jsonschema. `lammps` into `nativeCheckInputs`.

**`aiida-pythonjob`** — setuptools. Deps `aiida-core ase node-graph`. `pyproject.toml` sets
`addopts = "--pdbcls=IPython.terminal.debugger:TerminalPdb"`, which drags IPython in for nothing —
it only selects a debugger that never opens in a non-interactive run. Strip the line in `postPatch`
with `--replace-fail` rather than adding `ipython` to `nativeCheckInputs`.

**`aiida-phonopy`** — `hatchling`. Deps `aiida-core phonopy seekpath aiida-pythonjob`. `phonopy~=4.0`
against nixpkgs 4.4.0 is satisfied.

**`aiida-workgraph`** — `flit-core`. Deps `numpy scipy node-graph node-graph-widget aiida-core
cloudpickle aiida-shell aiida-pythonjob jsonschema`. Largest suite of the sixteen (42 modules), and
it depends on four things this plan adds, so it lands late. `node-graph~=0.6.5` and
`aiida-pythonjob~=0.5.2` are tight pins — check the clones' versions match before relaxing.

**`aiida-wannier90-workflows`** — `flit-core`. Deps `aiida-core aiida-pseudo aiida-quantumespresso
aiida-wannier90 click colorama`. `aiida-wannier90` is declared as a **git URL**
(`@ git+https://github.com/aiidateam/aiida-wannier90.git@v2.2.0`); `pythonRelaxDeps` cannot touch a
direct-URL requirement, so rewrite it to a bare name in `postPatch` with `--replace-fail`.

**`aiida-restapi`** — `flit-core`. Two problems beyond the ordinary:
1. `aiida-core @ git+https://github.com/aiidateam/aiida-core.git` — same direct-URL rewrite as
   above, and it must happen or the metadata check fails outright.
2. `lark~=0.11.0` against nixpkgs' 1.3.1. lark 0.11 → 1.0 was a real API break (the distribution
   was renamed from `lark-parser`, and `Lark`'s grammar handling changed). Relax, then run the
   query-parser tests and expect to patch. This is the one package here that may not build on the
   first pass.
   Also relax `fastapi~=0.115.5` (0.139) and `pydantic~=2.0`. Console script `aiida-restapi` →
   `meta.mainProgram`.

**`aiida-firecrest`** — `flit-core`. Needs tier-A `pyfirecrest`. Tests spin up a FirecREST server
(`firecrest_demo.py`) and set `timeout = 25`; if that cannot run offline, restrict `pytestFlags` to
the modules that do and say so in a comment — do **not** reach for `doCheck = false`
(`supply-test-deps-dont-disable` memory). Console script `aiida-firecrest-cli`.

**`sisl`** — the heaviest single item. scikit-build-core + meson + Cython + a Fortran compiler.
Budget for this separately; nothing else in the plan depends on it except siesta.

**`aiida-optimize`** and **`aiida_siesta_plugin`** — last. Siesta's deps are `aiida-core
aiida-pseudo ase seekpath sisl aiida-optimize`; `seekpath~=1.9` against nixpkgs' 2.2.1 needs
relaxing. Package name is `aiida_siesta_plugin`, module `aiida_siesta` — use `aiida-siesta` as the
Nix attribute for consistency with the other plugins, and note the mismatch in the derivation.

#### Registration — the three-to-four edits per package

Per `AGENTS.md` ("Adding a Python package takes three edits"), inside the `aiida` overlay in
`overlays/default.nix`:

1. `<name> = pself.callPackage ../pkgs/<name> { };` in the `pythonPackagesExtensions` attrset —
   **all twenty-two**. Sibling dependencies resolve through `pself`; do not thread them by hand.
   `pymatgen` and `jq` are the two exceptions already documented at their call sites.
2. Add to the top-level `inherit (final.python313Packages)` list — **plugins and apps only** (the
   fourteen `aiida-*` names). `node-graph`, `node-graph-widget`, `starlette-graphene3`,
   `pyfirecrest`, `sisl` and `aiida-optimize` stop at step 1, like `kiwipy`/`plumpy`/`aiida-pseudo`
   do today.
3. Add the same fourteen to the `inherit (py)` list in `default.nix`.
4. Add them to `exportedPackages` in `tests/aiida/default.nix` — the fourth hand-written copy that
   exists so the other three cannot drift. Anything that ends up `meta.broken` also goes in
   `brokenExportedPackages`, or `aiida-overlay-broken-set` fails.

`node-graph-widget-js` is a plain `final.callPackage` at the top of the overlay (it is not a Python
package) and is threaded into `node-graph-widget` explicitly.

#### Prose to update

- `overlays/default.nix` — the comment above the plugin block says "The six plugins." Rewrite for
  the new count and say which are new-dependency-bearing.
- `AGENTS.md` — the "What this is" AiiDA bullet (plugin count), and new rows in the pointer table
  for the decisions that end up non-obvious: the widget's npm build and the `skip-if-exists`
  interaction, the direct-URL rewrites in `aiida-restapi` and `aiida-wannier90-workflows`,
  aiida-lammps' jsonschema jump, and whatever `sisl` costs.

### Verification

Inside this sandbox (no daemon, evaluation only) after **each tier**:

```sh
just check-no-daemon        # eval suites, VM instantiation, parse over every tracked .nix
```

`just aiida-eval-tests` alone is the fast loop while editing the three registration lists — it is
what catches a name added to `overlays/default.nix` but not to `default.nix`.

Out of band, by you, one tier at a time — redirect to a log file so the transcript keeps it:

```sh
just build aiida-shell                                  # NUR path, one package
nix build .#aiida-shell -L --keep-going 2>&1 | tee log-shell
```

`--keep-going` matters: `AGENTS.md` warns that fixing the sdist trap on one package reveals the
next layer rather than finishing the job, and `--keep-going` reports every leaf per round instead
of the first.

For each package, before calling it done, confirm from the log that **pytest collected a non-zero
number of items**. A green build with `collected 0 items` is the trap, not a pass.

Then, once all tiers are in:

```sh
just check                  # both eval suites, every VM test, the hooks
just ci-matrix              # all three channels
XDG_CACHE_HOME=$TMPDIR just hooks
```

`nixConfig.extra-substituters` is ignored unless you are in `trusted-users` — check for
`warning: ignoring untrusted flake configuration setting` before blaming a hash.

### Out of scope

- Wiring any new plugin into `tests/aiida/vm.nix`. `aiida-shell` is the obvious candidate for a
  daemon-backed VM test later, since it can drive `pkgs.qchem.*` programs without a plugin each,
  but that is its own session.
- The previous worklog's other two follow-ups: a `just eval` recipe factored out of
  `scripts/no-daemon-check.sh`'s `locked_nixpkgs`, and `XDG_CACHE_HOME` for `prek` in
  `.claude/settings.local.json`.

---

## Out-of-band

Every build was the user's, in a separate terminal, since the Claude Code sandbox has no
nix-daemon. The results came back as files in the repo root, which is what each `read "log-*"`
prompt refers to:

| Log | What it settled |
|---|---|
| `log-fireworks` | the `zopen` fix worked; the 20 failures after it are xdist cwd collisions at `--numprocesses=128` |
| `log-shell` | `unzip`, a `#!/bin/bash` shebang, and `verdi` missing from the check PATH |
| `log-submission-controller` | `import aiida` cannot create `/homeless-shelter/.aiida` |
| `log-ase` | one stale `pbc` key in a TrajectoryData regression reference |
| `log-lammps` | `distutils` gone on 3.13; then a draft-2020-12 schema rejection; then `lmp` shadowed by a Python binding; then 8 build-specific regressions |
| `log-gromacs` | `procps`, then PLUMED |
| `log-nwchem` | five distinct failures in a row (see Outcome) |
| `log-probe-gromacs`, `log-probe-nwchem` | the two probe derivations, which is where the guessing stopped |

None of these commands is recoverable from the transcript, because they were run in another
terminal rather than through `!` in the prompt. Running them as `! just build aiida-nwchem`
would put both the command and its output in the transcript, which is what lets a later worklog
quote them exactly.

Final state, reported by the user: `just ci-matrix` and `just check` both pass.

## Changes

Committed as `b4b341e feat(aiida): package seven more plugins, plus sisl and aiida-optimize`,
on top of `14b035b fix(fireworks): pass an explicit mode to monty's zopen`.

| File | Why |
|---|---|
| `overlays/default.nix` | rebase conflict resolved; nine new `pself.callPackage` lines; seven added to the top-level `inherit`; `lammps` threaded from `final` |
| `default.nix`, `tests/aiida/default.nix` | the other two of the four registration lists AGENTS.md requires |
| `pkgs/aiida-shell` | flit-core; broker rewritten to `core.zeromq`; `unzip`, `which`, `procps`, coreutils, diffutils; `verdi` on the check PATH |
| `pkgs/aiida-submission-controller` | no test suite upstream; `HOME` for the import check |
| `pkgs/aiida-wannier90` | pytest-datadir for `shared_datadir`; no wannier90 binary needed |
| `pkgs/aiida-ase` | stale `pbc` regression patched; gpaw deliberately *not* a check input |
| `pkgs/aiida-nwchem` | two MPI ranks, `mpiCheckPhaseHook`, cell removed and coordinates rescaled, two assertions repaired |
| `pkgs/aiida-gromacs` | `flit_core >=4` relaxed in `[build-system]`; `procps`; PLUMED-enabled gmx; `-ntmpi 1` uncommented |
| `pkgs/aiida-lammps` | `distutils` to `shutil.which`; schema given a `$schema`; `--lammps-exec lmp`; 8 regressions deselected |
| `pkgs/sisl`, `pkgs/aiida-optimize` | dependencies of the unpackaged aiida-siesta; registered but not re-exported |
| `pkgs/fireworks` | `zopen` needs an explicit mode from monty 2026.7.16 |
| `scripts/offline-src-hash.sh`, `Justfile` | `just hash-src` — a fetchFromGitHub hash from a `wc/` clone, no network, no daemon |
| `AGENTS.md` | the AiiDA bullet rewritten for thirteen plugins; fifteen new pointer-table rows |
| `.scratch/nixpkgs-plumed-mpi.patch` | drafted upstream fix; AGENTS.md points at it |

## Outcome

### The method: probes, after two rounds of guessing

Two fixes went in on inference and both were wrong. `PLUMED_KERNEL` was proposed as the reason
the metadynamics tests produced no HILLS; it changed nothing. A hand-written `OMPI_MCA_pml=ob1`
plus `UCX_TLS` was proposed as the reason NWChem produced no output; it changed nothing. In both
cases the real message lived in `_scheduler-stderr.txt`, inside a retrieved `FolderData`, which
no assertion prints — so the build log could not distinguish the candidate causes and neither
could I.

What worked was `.scratch/probe-nwchem-plumed.nix`: two `runCommand` derivations that run the
same two programs directly, in the same kind of sandbox, with `set +e` around the interesting
command so they succeed and print everything. Every diagnosis below came from one of them, and
each cost one cached build rather than a full package rebuild. **Reach for that on the second
inference, not the fourth.**

### NWChem, five layers deep

Each fix revealed the next, which is the pattern AGENTS.md already warns about for recovered
suites:

1. **One rank.** nixpkgs builds NWChem with `ARMCI_NETWORK=MPI-PR`, which reserves a rank for
   communication progress, so two is the minimum. `conftest.py` pinned one:
   `Received an Error in Communication: (2) ranks per node, must be at least`.
2. **Periodic geometry.** All three tests hand the Gaussian DFT module a cell, and
   `src/nwdft/input_dft/dft_rdinput.F` has refused that since `3561a7eff3` (2021-08-29), first
   released in v7.2.0. nixpkgs has 7.3.1.
3. **Fractional coordinates.** Deleting the `system crystal` block is *not* enough, and this is
   the trap worth remembering: those coordinates are fractions of a 4 Å cube. Deleting the block
   alone reinterprets them as ångströms and shrinks the molecule to a 0.45 Å O–H, which still
   converges — to -72.06 — and *would have looked like a passing test*. Rescaling by `lat_a`
   restores O–H 1.8088 Å at 104.52°, and the resulting energy lands 0.058 from upstream's own
   -74.38 reference, which is what proves the reading.
4. **A vacuous assertion.** `assert pytest.approx(parameters['total_dft_energy'], 0.1, -74.38)`
   passes the reference as a *tolerance*, compares nothing, and asserts on the approx object.
   Under pytest 9 it errors outright. Repairing it exposed that the same line had been
   copy-pasted into a test running a different molecule, where the right reference is -74.73.
5. **A string.** `parsers/nwchem.py` does `result_dict[key] = result.group(2)` and never casts,
   so the repaired comparison failed on the type. The cast belongs in the test; changing the
   parser would change the package's output for every consumer.

### GROMACS + PLUMED is a real defect, not a test artifact

The user asked directly whether forcing `-ntmpi 1` hides a problem users will hit. It does hit
them, and the probe's rank sweep says exactly why:

```
default (128 tMPI)   exit 139   double free or corruption (fasttop)
-ntmpi 1             exit 0     HILLS, COLVAR and out.gro written
-ntmpi 2             exit 1     PLMD::Communicator::Set_comm: "you are trying to use an
-ntmpi 4             exit 1       MPI function, but PLUMED has been compiled without MPI support"
```

nixpkgs' `plumed` takes `buildInputs = [ blas ]` and nothing else. Serial is the only mode it
has, so the test patch aligns the suite with what the packaged library can do rather than
covering for the plugin — but a thread-MPI gmx takes a rank per core, so an unsuspecting user
gets the crash, not the diagnostic. `.scratch/nixpkgs-plumed-mpi.patch` is the upstream fix.

Its first draft was wrong in the usual way: `--enable-mpi`. PLUMED's `user-doc/Installation.md`
says that flag "is perfectly valid but is not needed here" and that "the correct way to enable
MPI is to pass to ./configure the name of a C++ compiler that implements MPI using the CXX
option"; `.github/workflows/linuxWF.yml` sets `CC=mpicc` and `CXX=mpic++` and passes no flag.
The patch now does that, and adds `--disable-mpi` on the serial branch, since MPI search is on
by default and finds `mpic++` first.

### Rejected, so it is not re-proposed

- **gpaw as a check input of aiida-ase.** The plan called for it. Nothing imports gpaw: the
  calculation tests assert on generated input and the parser tests replay stored output. It
  would have bought a large closure and changed nothing that runs.
- **`jsonschema` as "just a relax".** The API is unchanged, so the pin looked cosmetic. The real
  problem was the *default draft*: with no `$schema`, jsonschema 4 picks 2020-12 and rejects the
  schema's array-form `items`. draft-07 is the accurate declaration, not draft-04 — the file
  uses `propertyNames`, which draft-04 would silently ignore.
- **Patching only `rocket.py:150` in fireworks.** One of five bare `zopen` calls is reached by
  the suite; fixing that one alone would have looked green and left four `TypeError`s in the
  paths the mongomock partition never enters.
- **"`enablePlumed` costs a from-source GROMACS build in CI."** Stated confidently, then
  disproved by the probe log: cache.nixos.org has it. What it does change is the GROMACS version
  those three tests see, 2024.2 rather than 2026.3.
- **`PLUMED_KERNEL` as the fix.** Kept as cheap insurance for the runtime-linking case, but
  labelled as such: a serial run writes HILLS with or without it.

### Also fixed along the way

The rebase conflict in `overlays/default.nix` was `origin/main` adding a tenth pymatgen repair
(a `plt.close("all")` for a `van_arkel_triangle` flake) inside the block this branch had just
factored into the shared `pymatgenFor`. Resolution: keep the factoring, move the new `postPatch`
into the shared function, so both the `aiida` and `materials` overlays get it. The rendered
string was compared byte-for-byte against upstream's, since `''` dedents.

## Follow-ups

- **Three clones would unblock the rest of the plan.** `firecrest-streamer` (pyfirecrest imports
  `streamer` at module scope, so pyfirecrest and `aiida-firecrest` are blocked),
  `graphene-file-upload` (test-only, but `starlette-graphene3`'s conftest imports it, so
  `aiida-restapi` is blocked), and one online
  `nix run nixpkgs#prefetch-npm-deps -- wc/aiida/node-graph-widget/package-lock.json` for
  `npmDepsHash` (the esbuild bundle is not committed upstream, so node-graph-widget-js,
  node-graph-widget, node-graph and then aiida-pythonjob, aiida-phonopy and aiida-workgraph all
  wait on it).
- **`aiida-wannier90-workflows` and `aiida-siesta` are unblocked now** — `aiida-wannier90`,
  `sisl` and `aiida-optimize` all exist. They were simply not reached. Both need a direct-URL
  requirement rewritten in `postPatch`, which `pythonRelaxDeps` cannot touch.
- **Send the plumed patch upstream.** Once it lands,
  `gromacs.override { enablePlumed = true; enableMpi = true; plumed = plumed.override { enableMpi = true; }; }`
  gives the three metadynamics tests a parallel run instead of a serial one.
- **`fireworks` runs `--numprocesses=128` on a suite that chdirs into fixed directories.** The 20
  failures and 5 collection errors in the last `log-fireworks` are workers stamping on each other
  (`FileNotFoundError: 'test.json'`, `'././__pycache__/…'`). `dontUsePytestXdist = true` is the
  knob.
- **Delete `.scratch/probe-nwchem-plumed.nix`** — its own header says to, once both are
  diagnosed, and both are.
- **Proposed script — `scripts/check-postpatch.sh <package>`.** Rendering a `postPatch` with
  `nix eval`, then applying it to `git archive` of the matching `wc/` clone through a
  `substituteInPlace` stand-in, was built by hand eleven times this session. It caught three
  errors that would each have cost a build round-trip: a multi-line replacement mangled by the
  `''` dedent (twice) and a pattern that no longer matched after nixfmt reindented it. This is a
  stable step — every `postPatch` in this repo deserves it — and it belongs in the Justfile next
  to `hash-src`.
- **Proposed script — `scripts/eval-probe.sh`, again.** The `nix-store --print-fixed-path`
  preamble that resolves the locked nixpkgs offline appeared 27 times this session, after the
  2026-08-26 worklog already proposed it and this plan deferred it as out of scope. It has now
  earned it twice.
- **Proposed recipe — `just read-log <file>`.** Stripping ANSI escapes and grepping for the
  pytest summary happened 36 times. `scripts/demux-build-log.sh` already exists for the
  interleaved case; this is the simpler sibling.
