---
date: 2026-08-17
slug: cheminformatics-family
status: done
sessions: ["17e04775-65e0-41f2-b629-6c4a6c0f18c2"]
touches:
  - "pkgs/{morfeus-ml,qmzyme,dbstep,aqme,ccreg,digichem-core}/**"
  - "pkgs/aiida-gaussian/**"
  - "pkgs/{mdanalysis,griddataformats,mda-xdrlib,mrcfile,basis-set-exchange,colour-science,configurables,openprattle,lwreg}/**"
  - "pkgs/aiida-{cp2k,orca,octopus,psi4,quantumespresso}/default.nix"
  - "overlays/default.nix"
  - "tests/cheminformatics/**"
  - "tests/aiida/default.nix"
  - "tests/default.nix"
  - "flake.nix"
  - "default.nix"
  - "Justfile"
  - "scripts/no-daemon-check.sh"
---

# Package the cheminformatics family, and fix the cclib wiring it exposed

Follow-on to [2026-08-17 AiiDA ecosystem](2026-08-17-aiida-ecosystem.md), whose
"Follow-ups" named both halves of this: fill the five `lib.fakeHash` values, and
package the five `wc/` checkouts that arrived mid-session.

## Ask

> continue with where you left off.  create packages for the additional
> repositories in the "wc" subdir; you will likely need to fetch from github
> revs rather than tags from pypi.  remember to use the cclib flake.  tell me
> what build/test commands I should be running outside of the sandbox.

Then, while I was working around a broken sandbox:

> I think I fixed the crazy "command not found" problem

> ok, maybe not...

After I asked for eight dependency repositories to be cloned:

> ok, the extra repos are cloned

and, for `mrcfile`:

> clone done

Then the one report that changed the work — `just check`, run in a real
terminal:

> ```
> $ just check
> nix flake check -L
> warning: Git tree '/home/eric/data/development/nix/nur' is dirty
> warning: Ignoring the client-specified setting 'trusted-public-keys', because it is a restricted setting and you are not a trusted user
> error:
>        … while checking flake output 'packages'
>
>        … while checking the derivation 'packages.x86_64-linux.aqme'
>
>        … while evaluating the attribute 'optionalValue.value'
>          at /nix/store/2xyjmn6zr9jrd5kadcmaqjv0rl197kmk-source/lib/modules.nix:1312:5:
>          1311|
>          1312|     optionalValue = if isDefined then { value = mergedValue; } else { };
>              |     ^
>          1313|   };
>
>        (stack trace truncated; use '--show-trace' to show the full trace)
>
>        error: evaluation aborted with the following error message: 'lib.customisation.callPackageWith: Function called without required argument "xtb" at /nix/store/h20j5kma0pqshvf417cww104f5gjdx9g-source/pkgs/aqme/default.nix:26, did you mean "otb", "stb" or "xob"?'
> error: recipe `check` failed on line 94 with exit code 1
> ```

Finally, `/worklog`.

## Plan

**No plan-mode session.** The scope was inherited from the previous worklog's
follow-ups, and two scope questions were settled through `AskUserQuestion`
instead:

| Question | Answer |
|---|---|
| RMG-Py — seven missing packages, `numpy<2`, a 3.11 pin, and the separate RMG-database repo | "Skip it, deliver the other seven" |
| Four dependency packages neither in nixpkgs nor in `wc/`, so unreadable offline | "Clone them into wc/ first" |

The second answer is what made the rest possible: without the sources there was
nothing to write but guessed dependency lists and more `lib.fakeHash`.

## Out-of-band

**The sandbox lost its bind mounts.** Every `PATH` entry except `/bin` was gone,
`/run/current-system` did not exist, and `/bin` held only `bash` and `sh`. No
`git`, `nix`, `ls`, `tail` or `tr`. `/nix/store` was intact, so `PATH` was
rebuilt by globbing store paths for each tool and sourcing that from the
scratchpad on every command. The daemon socket exists but `socket(AF_UNIX)` is
still blocked, so nothing could be built — the same constraint as last session.

A side effect worth knowing: the forwarded dotfiles (`.bashrc`, `.gitconfig`,
`.mcp.json`, `.claude/agents` and a dozen more) landed as `/dev/null` character
devices **in the repository root**, where `git status` reports them as
untracked. They were never staged. They vanish on sandbox restart, but until
then `git add -A` in the repo root is unsafe.

The clone the user ran with `!` was line-wrapped by the terminal and died with a
shell syntax error before reaching `git`. It would have failed anyway — this
sandbox has no network — so both clone rounds were run outside it:

```sh
for r in MDAnalysis/mdanalysis MDAnalysis/GridDataFormats MDAnalysis/mda-xdrlib rinikerlab/lightweight-registration MolSSI-BSE/basis_set_exchange colour-science/colour Digichem-Project/openprattle Digichem-Project/configurables; do git clone --depth 1 "https://github.com/$r.git" "wc/${r##*/}"; done
git clone --depth 1 https://github.com/ccpem/mrcfile.git wc/mrcfile
```

The `just check` run above was pasted rather than run through `!`, but the
output was complete enough to act on.

## Changes

Nothing was committed — I stage and draft, the user commits. The message is at
`.git/cheminformatics-commit-msg.txt`.

**Seven packages from `wc/`**, all `fetchFromGitHub` at the checked-out rev.
`fetchPypi` was not used anywhere: none of these has a release matching what is
checked out, and DBSTEP, ccreg and QMzyme have no useful release at all.

| Package | Note |
|---|---|
| `morfeus-ml` | dist name is `morfeus-ml`, import name `morfeus`; `__init__.py` does `metadata.version("morfeus-ml")`, so the pname is load-bearing |
| `qmzyme` | `openbabel` declared but never imported anywhere in the tree — dropped with `pythonRemoveDeps` |
| `dbstep` | `dbstep.graph` kept out of the import check: it imports rdkit and pandas, which upstream keeps in the `graph2d` extra |
| `aqme` | every requirement is an `==` pin, so `pythonRelaxDeps = true` rather than a list |
| `ccreg` | drops its own `lwreg @ git+…` direct URL reference and adds rdkit/tqdm/psycopg, which upstream declares only under `[tool.pixi.dependencies]` |
| `digichem-core` | dist `digichem-core`, repo `digichem-library`, import `digichem` |
| `aiida-gaussian` | the sixth AiiDA plugin |

**Nine dependency packages**, reachable through `python313Packages` only:
`mdanalysis`, `griddataformats`, `mda-xdrlib`, `mrcfile`, `basis-set-exchange`,
`colour-science`, `configurables`, `openprattle`, `lwreg`.

**Two new overlays.** `cheminformatics` holds everything that does not need
cclib, injecting into `pythonPackagesExtensions` like the `aiida` one.
`cheminformatics-cclib` holds the four that do, as top-level
`python3.pkgs.callPackage` entries.

**`tests/cheminformatics/default.nix`** — five eval tests, dispatched from
`tests/default.nix`, added to `scripts/no-daemon-check.sh`'s `eval_suites` and to
`flake.nix` as `checks.eval-cheminformatics`.

**The five `lib.fakeHash` values are filled**, and `pkgs/aiida-gaussian` joins
`exportedPackages` in `tests/aiida/default.nix`.

## Outcome

`just check-no-daemon`: **69/69 eval tests PASS** (34 qcarchive, 30 aiida, 5
cheminformatics), all eleven VM tests instantiate, all four dotdrop tests
instantiate, 61 files parse. `nixfmt --check`, `statix`, `deadnix` and
`shellcheck` are clean. `ci.nix`'s `cacheOutputs` picks up `morfeus-ml` and
`qmzyme` and correctly excludes all six broken packages.

**Nothing was built.** No nix-daemon.

### The first real build: nixpkgs' aiormq

The user ran `just check` in a real terminal and kept the log as `log_check`
(76 KB, untracked). It is the first time anything here has actually been built,
and it found one root cause behind roughly forty cascading errors:

```
python3.13-aiormq> The 'aiormq' derivation has version '9.6.4' but .dist-info/METADATA specifies version '6.9.2'.
```

nixpkgs' `aiormq` fetches upstream's `9.6.4` tag — the tag exists and the hash
matches, so the source is right — but that tree's `pyproject.toml` still says
`6.9.2`. `pythonMetadataCheckPhase` makes that a hard failure, which takes down
`aio-pika`, and with it `kiwipy[rmq]` → `plumpy` → `aiida-core` → all four AiiDA
VM tests, `aiida-cp2k`, `aiida-pseudo` and `aiida-gaussian-datatypes`. **Nothing
to do with this session's packages** — it is a nixpkgs bug that the AiiDA session
could not have seen, because nothing was built then either.

Worked around in the `aiida` overlay by adding `pyprojectVersionPatchHook` to
aiormq's `build-system`, which is what nixpkgs' own error message recommends.
That override has to live in the package set rather than in a `let` binding —
unlike the pymatgen one — because the broken derivation is two levels down and
nothing here constructs it, so `aio-pika` can only pick up the fix through
`pself`. Verified as a real change rather than a no-op: the plain derivation is
`g0bm3s2wp2ykkq9m5g1cd0pakyn1wh5s`, exactly the one that failed in the log, and
the overlaid one is `8iamv8jy593m9ykjz0xc684dl6qbxwwr`.

A patch for nixpkgs itself was asked for and is **still open** — see Follow-ups.

### Three defects found, two of them pre-existing

1. **`overlays.harmonwig` had never resolved its cclib.** It used
   `final.python3Packages.callPackage`, and nixpkgs defines
   `python3Packages = dontRecurseIntoAttrs python314Packages` — an alias to the
   *versioned* set, not `python3.pkgs`. cclib's overlay overrides the `python3`
   attribute, so it never reached `python3Packages`; `callPackage` left the
   defaulted `cclib ? null` argument at null and produced a `meta.broken`
   harmonwig **on the flake path too**, with nothing to say so. Last session
   shipped this and it was invisible because nothing was ever built.
   `tests/cheminformatics`'s `cheminformatics-cclib-resolves` now asserts
   against it — verified by putting the bad spelling back and watching the test
   go FAIL.

2. **`nix flake check` forces every member of `packages`**, and forcing a
   `meta.broken` derivation throws. `aiida-gaussian` is broken on every path, so
   it would have taken the whole check down. `packages` now filters broken
   derivations out; they stay reachable through `legacyPackages`, which flake
   check does not force.

3. **`xtb` is not a top-level attribute of the nixpkgs NixOS-QChem pins** — it is
   `pkgs.qchem.xtb` there, from NixOS-QChem's own overlay — while
   nixpkgs-unstable has it at the top level. This is the error the user's
   `just check` hit. `aqme` now takes `xtb ? null` and the overlay passes
   `final.xtb or final.qchem.xtb or null`; with neither, two test files are
   skipped instead of the build aborting.

### The offline hash technique

`fetchFromGitHub`'s hash is the NAR hash of the unpacked codeload tarball, and
GitHub builds that tarball with the rules `git archive` follows, so:

```sh
git -C "$repo" archive --format=tar "$rev" | tar --extract --directory "$work"
nix hash path --type sha256 --sri "$work"
```

reproduces it exactly. Validated against harmonwig's known-good
`sha256-tSFj/1ZL...` **before** being relied on. This is what filled the five
`lib.fakeHash` values that last session recorded as blocked, and it produced
every hash in this session's sixteen new derivations.

### What was rejected, and why

- **Packaging RMG-Py**, and even leaving a `meta.broken` skeleton for it. It
  needs cantera, CoolProp, pydas, pydqed, symmetry, pysidt-rmg and pyutilib —
  none in nixpkgs, several Fortran/C++ and conda-only — plus `numpy<2`, a Python
  3.11 pin, and the separate multi-GB RMG-database repository. That is a project,
  not a package. Asked; the answer was to skip it.
- **Making `aiida-gaussian` buildable by adding the `aiida` overlay to
  `cclibPkgs`.** It would work — the package set is a fixpoint, so a
  `pythonPackagesExtensions` member does see the `packageOverrides` entries — but
  it rebuilds aiida-core's whole closure against the year-old nixpkgs
  NixOS-QChem pins rather than ours, producing a second, silently divergent
  AiiDA. Left broken and documented instead. **This is the open decision.**
- **Repackaging cclib** to escape Psi4 for `aiida-gaussian`'s sake. The previous
  session was told explicitly to use the flake, and that still holds.
- **Putting the cclib dependants in `pythonPackagesExtensions`.** They would land
  in `python313Packages`, which is exactly the set that never has cclib.
- **`with (import ./overlays); [ ... ]`** in `flake.nix`'s `cclibPkgs`. A `let`
  binding reads better and does not put a `with` scope around a list whose names
  matter.
- **Running colour-science's and MDAnalysis's full suites.** MDAnalysis ships no
  tests in its own distribution — they are a separate `MDAnalysisTests` dist with
  70 MB of fixtures in the sibling `testsuite/` directory. That is not
  `doCheck = false` in disguise, and the comment at the code says so.
- **A `tests/cheminformatics` suite that builds anything.** It asserts wiring
  only, using a stub overlay shaped like cclib's, so it runs in the no-daemon
  loop. Catching the `python3Packages` bug there costs a second; catching it in a
  flake build costs a Psi4.

### Corrections made during the session

- **`griddataformats` and `basis-set-exchange` had invalid PEP 440 versions.**
  The user changed `mda-xdrlib` and `qmzyme` from `X-unstable-YYYY-MM-DD` to
  `X.devYYYYMMDD`; the same string is substituted into versioningit's
  `default-version` and handed to `SETUPTOOLS_SCM_PRETEND_VERSION` in those two,
  which reject anything `packaging.version.Version` cannot parse. Both follow the
  PEP 440 form now; all four were checked against the real `packaging` library.
  Every other package keeps the nixpkgs `-unstable-` convention, which is correct
  where the string never reaches a Python build backend.
- **The pymatgen override moved** from `aiida-core`'s `callPackage` site to a
  `let` binding in the extension, because `aiida-gaussian` depends on pymatgen
  directly and hit the same `pythonAtLeast "3.13"` gate. It is still local, and
  `aiida-overlay-pymatgen-override-is-local` still asserts that.

## Follow-ups

- **Write the nixpkgs patch for `aiormq` and submit it.** Blocked on seeing
  upstream's tags: `9.6.4` and `6.9.2` are transposed digits and aiormq's real
  series is 6.x, so the fix is either `pyprojectVersionPatchHook` (upstream
  tagged and forgot to bump) or a corrected `version` (nixpkgs took the wrong
  number). Those are very different patches and guessing would mean a PR that
  ships a nonexistent version string. `git clone https://github.com/mosquito/aiormq.git wc/aiormq`
  settles it. Our overlay workaround should be removed once nixpkgs carries the
  real fix.
- **Re-run `just check` once aiormq builds.** The log stopped at that failure, so
  nothing past it — every AiiDA package, every VM test, and all sixteen new
  derivations — has been built even once.
- **Decide on `aiida-gaussian`.** Either accept a second AiiDA closure built
  against NixOS-QChem's nixpkgs, or leave the plugin unbuildable. Nothing else
  in the repo is in this position.
- **Build the tiers, in order, and do not batch past a failure.** The commands
  are in the commit message and were given in-session; `mdanalysis` failing
  invalidates `qmzyme`, and the cclib five need `trusted-users` or Psi4 compiles
  from source.
- **Verify `fetchFromGitLab` hashes the same way.** `aiida-octopus` is the only
  GitLab source here and its hash was computed with the same method, but the
  method was only validated against a GitHub known-good value.
- **Proposal — `scripts/githash.sh` and a `just githash <checkout> [rev]`
  recipe.** The `git archive | tar x | nix hash path` sequence was run for
  sixteen derivations this session and is the only way to get a hash without
  network or daemon. It currently lives in the scratchpad, which is ephemeral.
  It is shellcheck-clean and four lines long.
- **Proposal — teach `scripts/no-daemon-check.sh` to rebuild `PATH` from the
  store** when the sandbox has lost its bind mounts. Reconstructing it by hand
  cost the first twenty minutes of this session, and the script is the repo's
  designated entry point for exactly this environment. The previous worklog
  already proposed the `git`/`jq` fallback half of this.
- **Proposal — integration suites for the new CLIs**, modelled on
  `tests/harmonwig`. `dbstep`, `ccreg` and `aqme` all have console scripts and
  none has a suite here. They would need the flake's `cclibPkgs`, so they cannot
  be written blind from the sandbox.
