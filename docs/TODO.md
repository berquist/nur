# TODO

Standing work items that outlive a single session. Worklogs in `.claude/worklog/` record what
happened; this records what has not happened yet. One heading per item, newest first.

## basis-set-exchange's `--runslow` suite (tabled)

**Want:** a decision about whether any of upstream's slow suite is worth running here, and if so
which part — not the whole thing.

`basis_set_exchange/tests/conftest.py` defines a `--runslow` option.  Without it,
`pytest_ignore_collect` drops all eight `*_slow.py` modules and `pytest_collection_modifyitems`
skips anything marked `slow`, which is most of what `pkgs/basis-set-exchange` reports as skipped.
It was turned on once, with pytest-xdist, and turned off again on the strength of the numbers:

    798,417 collected · 788,216 passed · 10,201 failed · 1,570 skipped
    4 h 12 m at 32 workers

**The failures are upstream's converters refusing basis sets they cannot express**, not anything
packaging did.  Nearly all of them are in `test_api_slow.py`, and they group tightly:

| Count | Failure |
|---|---|
| 3,072 | `Converter veloxchem does not support all function types: {'sc…` |
| 3,072 | `Converter fhiaims does not support all function types: {'scal…` |
| 1,568 | `ECP contains l=5 term but Crystal format only supports up to …` |
| 672 | `Converter veloxchem does not support all function types: {'gt…` |
| 576 | `Electrons cover a partial shell. 9 electrons left` |
| 256 | `KeyError: 'electron_shells'` |

`test_convert_slow.py` adds about a thousand more of the same flavour — regexes that do not match
a reader's own output, MD5 mismatches, `jsonschema` validation failures on empty lists.

**What a plan here would have to settle**, none of which is a packaging question:

1. Whether upstream's CI runs this at all.  If it does not, a green run may never have existed and
   "10,201 failures" is the normal state rather than a regression.
2. Whether the per-converter refusals are assertions about what *should* work, or the suite simply
   enumerating every (format, basis) pair and letting the unsupported ones raise.  The wording
   suggests the latter, in which case these are not failures so much as an unfiltered matrix.
3. If some subset is genuinely meaningful, which modules — `test_lut_slow.py` is 18 failures and
   might be tractable on its own, where `test_api_slow.py` is not.

**Until then the option stays off**, and the reasoning lives at `pkgs/basis-set-exchange`'s
`nativeCheckInputs`.  pytest-xdist stays on: it is right for this suite either way, and it is what
made measuring the above possible at all.

## Stop missing `nix-qchem.cachix.org`

**Want:** the packages this repository takes from NixOS-QChem to come out of NixOS-QChem's own
binary cache, instead of being rebuilt from source.

**The miss is caused here, deliberately, and by one line.**  `qchemPkgs` in `flake.nix`
reproduces NixOS-QChem's instantiation exactly — its nixpkgs pin, `allowUnfree`, and the
`qchem-config` from its own `cfg.nix` with `allowEnv = false` and `optAVX = true` — except that
it rewrites `python3` to the interpreter `services.qcfractalCompute` would run.  That rewrite is
what `nixos-modules/qcfractal-compute.nix` asserts on: QCEngine imports a Python QC program into
the worker process, so a program built for another Python is unusable.

The cache is keyed on the derivation hash, so changing the interpreter changes it, and Psi4 and
its whole Python closure are rebuilt.  `nix-qchem.cachix.org` is in `nixConfig.extra-substituters`
and is not being used for the thing it was added for.

**It is already narrower than it looks, and knowing that is half the answer.**  The rewrite only
matters to packages that hang off `python3`.  `qchem.packmol` is a gfortran build of a single
Makefile and reads no interpreter at all, so `checks.fairchem-data-oc` gets a cache hit today;
the same goes for `qchem.crest` and `qchem.xtb`, which `pkgs/aqme` reaches.  Psi4 is the
expensive one, and CFOUR would be if anything here wanted it.

**Options, none of them costed yet:**

1. *Move this repository's Python pin to whatever `nixpkgs-qchem` calls `python3`.*  The comment
   at `qchemPkgs` already says the override "becomes a no-op the moment the two agree again".
   The pin is `python313` and NixOS-QChem's list carries `qchem.python312`, so today they do not
   agree.  Cheapest if the versions ever line up on their own; not something to force.
2. *Take Psi4 from `nixos-qchem.packages.${system}.psi4` — their built output — and drop the
   interpreter invariant for it.*  Rejected once already, and the note at `psi4` says why: that
   output is a `filterAttrs` over the entire qchem set, so selecting one package forces the
   predicate for every other one, and `builtins.tryEval` does not catch signature drift.  A
   single broken package anywhere in NixOS-QChem then takes down the whole `checks` output.
3. *Ask NixOS-QChem to build more than one interpreter*, or to make the interpreter a
   `cfg.nix` knob their Hydra sweeps.  Upstream work, and the only option that fixes this for
   good rather than by coincidence.
4. *Accept it and scope it*: keep the invariant, and make sure nothing new takes a
   Python-flavoured package out of `qchemPkgs` without knowing it pays for a rebuild.  This is
   the status quo, and it is defensible — it is simply not written down anywhere until now.

**Measure before choosing.**  Nobody has timed a cold `nix build .#checks.x86_64-linux.eval` or
a Psi4-backed VM check against a warm one, so "expensive" here is inferred from Psi4 being large,
not from a number.

## Report fairchem's `test_unified_matches_per_layer` tolerance upstream

**Want:** the tolerance in `tests/core/models/uma/nn/test_unified_radial.py` raised, or its fixture
made physical, so `pkgs/fairchem-core` can drop its one `disabledTests` entry.

**The test compares two orderings of the same arithmetic.** `UnifiedRadialMLP` `torch.stack`s
eight `RadialMLP`s' weights into batched buffers and does one batched matmul; the reference runs
eight separate ones. Same result in exact arithmetic, different reduction order in float32, so the
last bits differ — and which bits differ depends on the BLAS kernel, so this will pass on some
machines and fail on others.

**What makes `atol = rtol = 1e-6` unreachable** is the fixture rather than the comparison. It
overwrites *every* parameter with `torch.randn_like`, LayerNorm scales included, where those are
normally 1:

```python
mlp = RadialMLP(edge_channels)   # edge_channels = [64, 128, 128, 256]
for param in mlp.parameters():
    param.data = torch.randn_like(param.data)
```

Pushed through three layers at those widths the intermediates are far larger than in a trained
model, and float32 spacing at that magnitude is already around 1e-5 — an order of magnitude above
the tolerance being asserted.

**Either fix works:** leave the LayerNorm parameters at their initialised values, which is what a
real model has, or raise the tolerance to something float32 can honour at these magnitudes.

**Not diagnosed further here, and one thing to know before trying.** The test passes
`msg=f"Layer {i} output mismatch"` to `torch.testing.assert_close`, and that *replaces* the default
message — so the failure never reports how large the discrepancy actually was. Delete the `msg=`
and the numbers appear; that is the first step for anyone confirming the reasoning above, which is
argued from the shapes rather than measured.


## Build the internal packages that nothing else builds

**Want:** `just ci-matrix` to fail when an internal package breaks, instead of the breakage
sitting unnoticed until someone builds it by hand.

`ci.nix` walks `default.nix` and skips `python313Packages` — deliberately, and the note there
explains why: it is the whole 3.13 set, so descending would try to build all of nixpkgs.  The
consequence was not thought through.  Of the 138 packages this repository defines, 68 are
re-exported as top-level attributes and **70 are internal**, reachable only through
`python313Packages`.

Most of those 70 are still built, as build-time dependencies of something re-exported —
`plumpy` and `kiwipy` come along with `aiida-core`, `doped` and `pydefect` with `shakenbreak`.
The gap is the ones reachable **only through an `optional-dependencies` entry**, because an
extra is not a build input of the package that declares it.  Nothing builds those at all:

    sevenn            matcalc[sevennet]
    tensorpotential   matcalc[grace]
    deepmd-kit        matcalc[deepmd]        and dargs beneath it
    dpdata            deepmd-kit[dpa-adapt]  an extra of a package that is itself
                                             only an extra — two levels down,
                                             and parmed and dpdata-plugin-test
                                             sit under it for its check phase
    fairchem-core     matcalc[fairchem], quacc[mlip]
                                             and clusterscope, ase-db-backends beneath it
    fairchem-data-oc  quacc[fairchem]
    fairchem-data-omat  quacc[fairchem]
    fairchem-data-omol  quacc[fairchem]
    maml              matcalc[maml]
    rootstock         quacc[mlip]

**This is not hypothetical.** `pkgs/sevenn` was committed in caeb7af saying "Not build-verified
— the sandbox has no nix-daemon", and stayed that way.  The first time it was ever built, months
later, it failed: all eleven tests in `test_pretrained.py` download a checkpoint from github.com.
A green `ci-matrix` said nothing about it either way.

**Options, roughly in order of preference:**

1. Give `default.nix` a second exposed set — say `internalPackages`, carrying
   `recurseForDerivations` where `python313Packages` carries `dontRecurseIntoAttrs` — holding
   exactly the packages this repo defines but does not re-export.  `ci.nix` then picks it up
   without any risk of descending into nixpkgs.  Costs a fourth hand-maintained list, which
   `tests/*/default.nix` already shows the shape of.
2. Have `ci.nix` build every package named by an `optional-dependencies` attribute of a
   re-exported package.  Narrower, and automatic, but expresses the rule obliquely.
3. Re-export them.  Rejected: `AGENTS.md` explains why single-dependant packages stay internal,
   and `tensorpotential` cannot be a top-level attribute at all without breaking `just ci-eval`.

Whichever is chosen, expect the first green run to take a while: these are torch-sized closures,
and several of them have never been built on any channel.


## Package the remaining fairchem distributions

**Want:** nothing urgent any more.  `quacc[fairchem]` is wired — `fairchem-data-omol`,
`fairchem-data-omat` and `fairchem-data-oc` are packaged beside `pkgs/fairchem-core` — and no
package in this repository asks for any of the nine distributions left.  This is a survey kept so
it does not have to be redone, not a queue.

Every one of these was written off in `AGENTS.md` as "13-distribution monorepo, torch plus
pretrained model weights", which counted the distributions instead of reading their dependency
lists.  Reading them:

| Distribution | Core dependencies | Gap |
|---|---|---|
| `fairchem-data-omol` | `ase` | **done** — plus numpy/scipy/pymatgen, undeclared |
| `fairchem-data-omat` | `pymatgen` | **done** |
| `fairchem-data-oc` | numpy, scipy, matplotlib, ase, pymatgen, tqdm | **done** — plus `fairchem-core`, undeclared |
| `fairchem-data-odac` | `ase`, `pymatgen` | none |
| `fairchem-data-omc` | + `atomate2` | none — atomate2 is packaged |
| `fairchem-demo-ocpapi` | dataclasses-json, inquirer, responses, tenacity, tqdm | none |
| `fairchem-applications-cattsunami` | `fairchem-core`, `fairchem-data-oc` | none, now |
| `fairchem-applications-fastcsp` | + `p_tqdm`, `rdkit` | `p-tqdm` |
| `fairchem-applications-ocx` | + matminer, plotly, statsmodels, seaborn, `yellowbrick` | `yellowbrick` |
| `fairchem-applications-AdsorbML` | declares none | read `setup.py` first |
| `fairchem-lammps` | `fairchem.core` + LAMMPS | not surveyed |
| `fairchem-core-numpy126` | a numpy-1.26 variant of core | skip — pointless here |

Each builds from its own `packages/<name>/` with the same `src -> ../../src` symlink, so they are
`sourceRoot` copies of `pkgs/fairchem-core` with a different tag; note the tags are
per-distribution (`fairchem_data_omol-0.1.2` and so on), not one repository-wide version.

**Two things this entry got wrong, worth knowing before trusting the rest of it.**

*It said packaging `fairchem-data-omol` would unblock `tests/core/components/test_omol_recipes.py`.*
It does not.  That module does need `fairchem.data.omol` to import, but it also carries
`pytestmark = [pytest.mark.pretrained("uma-s-1p1")]` at module scope and an autouse
`pretrained_checkpoint` fixture, so every one of its thirteen tests downloads a UMA checkpoint
from Hugging Face before `setUp` returns.  It stays in `disabledTestPaths`, for the same reason
the other eight modules there do.

*It called the three data packages "close to free".*  Two of them were.  `fairchem-data-oc` was
not: it needed a pin past its own tag, an undeclared dependency on `fairchem-core`, and a 36 MB
`fetchurl` for the bulk database that six of its seven test modules open.  See its derivation.


## Use fairchem's own `--exclude-models` instead of nine `disabledTestPaths` entries

**Want:** `pkgs/fairchem-core`'s deselections expressed the way upstream expresses them, so the
list stops needing to be rediscovered every time a test module is added.

Nine of the fourteen entries in that derivation's `disabledTestPaths` are there because the test
downloads a pretrained checkpoint from Hugging Face.  Upstream has a mechanism for exactly this,
and this repository is not using it: `tests/conftest.py` registers a `pretrained` marker, every
such test declares the model it wants through it, and the conftest adds an `--exclude-models`
option that deselects tests by declared model.  Their own `CLAUDE.md` records the rule — "Tests
that download registered checkpoints must declare their models with a `pretrained` marker.  This
lets base CI deselect them with `--exclude-models`".

So the shape is probably `--exclude-models=uma-s-1p1` (plus whatever else the suite declares) in
`pytestFlags`, replacing nine paths with one flag that stays correct as modules come and go.

The marker's coverage has been checked against the current list and the two agree, which is what
makes this worth doing rather than a guess.  Fifteen modules under `tests/core` carry
`pretrained`; nine are in `disabledTestPaths`, and the other six — `test_batcher.py`,
`test_calculator_extensivity.py`, `test_hessian_predict.py`, `test_inference_serve.py` and the two
already counted under another reason — are covered by `gpu` instead, either at module scope or on
every test function they define.  So the flag would subsume the nine and change nothing else.

**Not done here because it needs a build to verify**, and one detail has to be got right rather
than assumed: `--exclude-models` validates each token against the model registry and errors on an
unknown one.  That is the good failure mode — a typo is loud rather than a silent no-op — but it
does mean the argument list has to be complete and correct the first time, and the registry is
what decides, not the test files.

## Decide whether to allow cudaSupport

**Want:** a decision, and if it is yes, `nixpkgs.config.cudaSupport` allowed for consumers who
opt in, while `just ci-matrix` keeps building and caching the CPU closure only.

Nothing here is CPU-only by choice.  `config.cudaSupport` is `false` — nixpkgs' default — so
`python313Packages.torch.cudaSupport` is false and every torch dependant in this repo follows.
`pkgs/deepmd-kit` is the one place a CPU decision is written down (`DP_VARIANT = "cpu"`), and
that is downstream of the same fact: building CUDA kernels against a CPU-only torch is wasted
work.  If this goes ahead, that line is the one to revisit.

The concern that kept it out was that CUDA makes much of the closure unfree and enormous, which
`ci.nix` filters on (`meta.license.free`) and cachix would have to carry.  **That concern is
answered by not doing either**: allow the option, do not add it to the matrix, do not push CUDA
artifacts to cachix.  The work is then:

- confirm `ci.nix`'s `isBuildable` still excludes the CUDA variants — it filters on
  `meta.license.free`, and the CUDA closure is unfree, so this may already hold for free
- confirm `just ci-matrix` and `just push` are unaffected, since they go through `ci.nix`
- decide where the opt-in lives: a consumer setting `nixpkgs.config.cudaSupport` themselves and
  taking `overlays.materials`, versus anything this repo exports
- check that `just ci-eval` does not throw on an unfree *top-level* attribute the way
  `tensorpotential` would — see the note at that overlay binding

`nvalchemi-toolkit-ops` is a separate question and does not depend on this one; see below.

## Package nvalchemi-toolkit-ops (tabled)

**Want:** a survey, then a decision.  This is the single package blocking `torch-sim`,
`orb-models`, `mattersim` and `pet-mad`, and 9 of the failures in a full `pkgs/fairchem-core`
test run (`RuntimeError: Requires ``nvalchemiops`` to be installed`).  It is a core dependency of
those four, not an extra.

**Not started, and nothing has been read.** It has been recorded as a wall for weeks on the
strength of its name and its appearance in dependency lists — which is exactly the reasoning that
turned out to be wrong for `deepmd-kit`, for `fairchem-core`, and for the fairchem data packages
above.  It needs a clone and a read of its `pyproject.toml` before anyone says again that it
cannot be done.

Ask for the clone; it is not in `wc/`.


## Send `ase-db-backends`' `close()` fix upstream

**Want:** `pkgs/ase-db-backends/close-must-not-reopen.patch` offered to
[gitlab.com/ase/ase-db-backends](https://gitlab.com/ase/ase-db-backends), so we can drop it.
Unlike the enumlib item below, this one needs no further diagnosis and no verification work —
the patch is written, applies to HEAD, and the build that motivated it is the test.

**The bug.** `LMDBDatabase.close()` reaches the environment through the `env` property:

```python
@property
def env(self):
    if self._env is None or self._env_pid != os.getpid():
        self._open_lmdb_env()
    return self._env

def close(self) -> None:
    self.env.close()

def __del__(self) -> None:
    self.close()
```

Reopening after a fork is right for every reader of that property except this one.  On the close
path it inverts the meaning: closing an already-closed database *opens* it, and closing one in a
forked child opens a second handle to the parent's file, because `_env_pid != os.getpid()` is
precisely what a fork guarantees.  `__del__` calls `close()`, so it runs at garbage collection.

py-lmdb keeps a process-wide registry of open environment paths and refuses a second `open()` of
one, so this does not leak quietly — it raises `lmdb.Error: The environment '...' is already open
in this process.` from inside `__del__`, and the path stays registered, so every later
`connect()` in that process fails too.

**What it costs downstream.** It is not confined to tests: any program that opens an `aselmdb`
database twice in one process hits it, which includes `pkgs/fairchem-core`, where a dataset and
its splits are separate handles.  Applying the patch removes the `__del__` failures from the
build log entirely.

**Two further defects in the same area**, which the patch does not address.  Both open one LMDB
path twice in a single process — `test_aselmdb_concurrency` across eight forked workers,
`test_db2` nested inside its own context manager — which py-lmdb 2.x refuses outright.  Neither
is deselected any more: `overlays/default.nix` pins py-lmdb to 1.7.3, which predates that
restriction, so both modules run.  They are still worth mentioning upstream, because the code
will break again whenever ase-db-backends moves to py-lmdb 2.x.

**The pin now costs something in the other direction too**, and this is the ledger to keep if it
is ever revisited.  `pkgs/dpdata` requires `lmdb>=2.0.0` and is relaxed onto 1.7.3, which
deselects three of its tests: all three assert that a second open *raises*, which is precisely
what 2.0.0 added.  So the pin buys back two ase-db-backends modules and about 43 fairchem-core
failures, and sells three dpdata tests.  It is still the right trade by a wide margin — but it is
a trade, not a free win, and `pkgs/dpdata`'s `disabledTests` is where the receipt is.

**And one that is not upstream's fault at all**, worth knowing before reading a failure here:
`test_db` populates its database by shelling out to a nine-stage `ase -T build … | ase -T run
emt …` pipeline under `subprocess.run(..., shell=True)` and never checks the return code.  With
`ase`'s console script absent from PATH the pipeline fails silently and the test dies much later
with `KeyError: 'no match'`.  `pkgs/ase-db-backends` puts `ase` in `nativeCheckInputs` for it.
Upstream might reasonably be asked to check that return code.

**Worth asking upstream about at the same time:** whether their `lmdb` requirement wants an upper
bound. `pkgs/fairchem-core` relaxes fairchem's own `lmdb <= 1.7.3` cap to take nixpkgs' 2.3.0,
and it is not clear from either side whether that cap exists for this or for something else.


## Repair `compare_enum_files.x`, and send the patch upstream

**Want:** `aux_src/compare_two_enum_files.f90` compiling again, so that
`pkgs/enumlib` can build `compare_enum_files.x` rather than excluding it — and the fix offered
to `msg-byu/enumlib`, since this is upstream's bug and nothing about our build.

**Why it is excluded today:** see the `buildPhase` note in `pkgs/enumlib/default.nix`. Two
independent defects, both hard errors on any gfortran since 10. Neither has anything to do with
Nix, and both have been sitting in `main` for years — upstream's `.travis.yml` is from 2014-16
and so predates both, which is why its own CI never caught them.

**The diagnosis is already done. Both fixes are determined, not guesses:**

1. *Four `write` statements with a commented-out continuation.* Commit 557db14 (2019-09-10,
   "cleaned up comments, debug write statements, etc.") put a `!` in front of the second half of
   four format strings while leaving the trailing `&` on the line before, so the literal is never
   closed:

   ```fortran
   write(13,'("Volume is too big for structure #: ",i9," in file 2 (label # ", &
        !& i9,")")') iStr2, strN2
   ```

   The intent is unambiguous — the statement passes two integers, `iStr2, strN2`, and only the
   commented half carries the second `i9`. Dropping the four `!` characters restores it. That
   commit is the last one to touch the file, so it has not compiled since.

2. *A stale call signature.* Commit f6694db (2021-08-16, "updates from spring 2021 to help
   inactive site extension to uncle") changed

   ```fortran
   SUBROUTINE get_dvector_permutations(pLV,d,nD,rot,shift,dRPList,LatDim,eps)
   ```

   to drop `LatDim`, and did not update this file's two call sites (lines 101 and 217), which
   still pass eight arguments. That is why gfortran reports both "More actual than formal
   arguments" and "passed INTEGER(4) to REAL(8)" — `LatDim1` lands in the `eps` slot. Deleting
   `LatDim1` / `LatDim2` from the two calls is the whole fix; the interface has no such parameter
   any more, so there is nothing to choose between.

**What is actually left to do**, and why this is a TODO rather than a patch already applied:
compiling is not the same as working. 557db14 landed in the middle of a rewrite of the compare
algorithm (6d6cf3a, e5df546, three weeks earlier, "Finally appears to be working", "there is
still an n=6 case that is not passing"), and the program has not been built by anyone since. So
the work is to apply both fixes, build it, and then find something to check the result against —
`support/compare` and `support/comparetests.py` are upstream's own harness for exactly this
program and are the obvious place to start. Only then is it worth sending, and only then is it
worth adding to `pkgs/enumlib`'s target list.

**Not urgent.** Nothing in this repo uses `compare_enum_files.x`; pymatgen's `EnumlibAdaptor`
wants `enum.x` and `makestr.x` alone.

## A deterministic check that every declared input is actually required

**Want:** a tool that, for each package in `pkgs/`, proves each entry in its argument list is
load-bearing — and fails when one is not.

**Why:** nothing currently catches a dependency that is declared but unused. `qe-tools` carried
`xmlschema` through several sessions; it is neither in upstream's `dependencies` at the packaged
tag nor imported anywhere in the 2.x source. It came from reading the wrong version's metadata,
and no check noticed. The same class of error runs the other way too: `qe-tools` was *missing*
`scipy`, which `pythonRuntimeDepsCheckHook` did catch, but only at build time and only because
upstream declared it.

So there are two directions, and only one is covered today:

| | declared but unused | used but undeclared |
|---|---|---|
| Runtime deps | **nothing checks this** | `pythonRuntimeDepsCheckHook`, at build time |
| Check inputs | **nothing checks this** | test failure, at build time |

**Shape it might take.** The honest version is a rebuild bisection: drop one input, rebuild, and
assert the build fails. That is deterministic and needs no heuristics, but it is `O(inputs)` full
builds per package, so it belongs in a `just` recipe run deliberately rather than in CI.

A cheap approximation worth having first: parse the derivation's argument list, then grep the
built package's source tree for each name's import spelling. It has false positives — plugins
discovered through entry points (`pytest-cases`, `pgtest`), build-system hooks, and programs
invoked via `subprocess` rather than imported (`xtb`, `crest`, `cp2k`) all look unused to a
grep — so it should report suspects, not fail a build.

**Prior art to check before writing anything:** `deptry` does exactly this for Python projects
(declared-but-unused, undeclared-but-imported, misplaced dev deps) and reads `pyproject.toml`.
`morfeus` already configures it (`[tool.deptry]` in its `pyproject.toml`). It answers the
*upstream* question rather than the Nix one, but for a repo that is almost entirely
`buildPythonPackage`, running `deptry` against each unpacked source and diffing its verdict
against our argument list would cover most of the gap for far less work than a bisection.

**Constraint:** whatever this becomes, it must not need a nix-daemon to report the
declared-but-unused direction — that is the half that can be answered from source, and the
sandbox this repo is usually developed in cannot build anything. See the `no-daemon-check` skill.
