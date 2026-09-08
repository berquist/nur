# TODO

Standing work items that outlive a single session. Worklogs in `.claude/worklog/` record what
happened; this records what has not happened yet. One heading per item, newest first.

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

**Two further defects in the same area**, which the patch does *not* address and which are why
`pkgs/ase-db-backends` deselects two modules.  Both open one LMDB path twice in a single process,
which py-lmdb refuses; in both the first handle is still legitimately open, so no change to
`close()` could help.

- `test_aselmdb_concurrency` shares a single `LMDBDatabase` across eight forked workers, relying
  on the `env` property to reopen in each child.  py-lmdb's registry of open paths is inherited
  across the fork, so that reopen collides every time.  Fixing it means the child clearing the
  inherited registry, or not sharing the handle at all.
- `test_db2` opens the same path nested inside its own context manager — `with connect(name) as
  c:` and then `c = connect(name)` — which cannot work against any py-lmdb that has the registry.

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
