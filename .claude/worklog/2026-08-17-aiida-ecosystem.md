---
date: 2026-08-17
slug: aiida-ecosystem
status: partial
sessions: ["a363f523-52f0-4423-8294-3f3bfaf7d489"]
touches:
  - "pkgs/aiida-*/**"
  - "pkgs/{archive-path,disk-objectstore,kiwipy,plumpy,pgsu,pgtest,pytray,upf-to-json,qe-tools,cp2k-output-tools,postopus}/**"
  - "pkgs/harmonwig/**"
  - "nixos-modules/aiida.nix"
  - "overlays/default.nix"
  - "tests/aiida/**"
  - "tests/harmonwig/**"
  - "flake.nix"
  - "default.nix"
  - "Justfile"
  - "scripts/no-daemon-check.sh"
---

# Package the AiiDA ecosystem and harmonwig

## Ask

> Create new packages for each of the projects in the "wc" directory.  The AiiDA ones should have
> their own eval and VM tests in a subdirectory just like QCArchive.  I believe that since AiiDA
> (aiida-core) runs as a daemon, it should also have an optional module.  When it comes time to
> pick a database, use Postgres instead of SQLite.  When referencing documentation, prefer what
> exists in the repositories rather than searching the internet, especially for aiida-core.  Feel
> free to use non-nixpkgs inputs if nixpkgs doesn't have the dependencies.  Same as before, if
> neither nixpkgs nor NixOS-QChem have what you need, implement the package(s).

Four decisions were then taken through `AskUserQuestion`, before the plan was written:

| Question | Answer |
|---|---|
| Source | "Releases where they exist, wc rev otherwise" |
| Broker | "ZeroMQ default, RabbitMQ optional" |
| VM depth | "Also one real plugin round trip" |
| Plugins | all five AiiDA plugins, plus harmonwig |

The **first `ExitPlanMode` was rejected.** I stopped and reported four discrepancies a
late-arriving survey agent had turned up, and the reply was:

> Nothing is really wrong with the plan; it looks good so far.  For cclib, don't repackage it; use
> the flake provided in https://github.com/cclib/cclib/commit/545fa9bdd25af7b6e70d3323d4156791dd54a440,
> which I've check out into the "wc" dir.  For aiida-orca, use the latest SHA, not the latest
> release.  Don't set "doCheck = false"; figure out how to adapt the package(s) so that they can
> run their tests.  In the case of downloading, if that means packaging whatever the tests
> download and then patching the package to not download, do that.

The plan was revised accordingly and the second `ExitPlanMode` was approved.

One mid-turn interrupt, while I was halfway through moving the whole AiiDA family to `python312`
to escape nixpkgs' pymatgen interpreter gate:

> Let's try and override that pymatgen disabled instead

Then, after the usage-limit checkpoint and a `/compact`:

> continue

## Plan

Approved from `~/.claude/plans/create-new-packages-for-parsed-garden.md`, inlined in full.

---

### Context

`wc/` holds eight upstream checkouts. Seven are the packaging targets: `aiida-core` and five of its
quantum chemistry plugins (`aiida-cp2k`, `aiida-orca`, `aiida-octopus`, `aiida-psi4`,
`aiida-quantumespresso`), plus `harmonwig`, an unrelated standalone CLI. The eighth, `cclib`, is
there because it carries its own flake, which is where cclib will come from rather than a
derivation in this repo.

**Nothing in this list is in nixpkgs** — a case-insensitive grep for `aiida` across the locked
nixpkgs returns only hash-string false positives — and NixOS-QChem has none of it either. Neither
do eleven of the transitive dependencies.

AiiDA runs a daemon (a `circus` arbiter supervising worker processes), keeps its state in
PostgreSQL, and discovers plugins through Python entry points. That makes it a NixOS service in
exactly the way QCFractal already is here, so this work reuses the shape the repo has settled on:
package derivations under `pkgs/`, a named overlay per family in `overlays/default.nix`, one NixOS
module per service, and a `tests/<subject>/` directory holding an eval suite and a VM suite.

The outcome is `nix build .#aiida-core`, `services.aiida.enable = true` producing a working profile
against local PostgreSQL, and a VM test that runs a real CP2K calculation end to end through
`aiida-cp2k`.

### Decisions taken

| Question | Answer |
|---|---|
| Source | PyPI release where one exists; the `wc/` checkout's git rev otherwise |
| aiida-orca | the `wc/` SHA, **not** the latest release |
| cclib | the upstream flake, not a derivation here |
| Broker | `core.zeromq` by default (needs no external service), `core.rabbitmq` behind an option |
| VM depth | Daemon up + `core.arithmetic.add_multiply`, **plus** one real plugin round trip |
| Plugins | All five, plus harmonwig |
| Tests | **No `doCheck = false`.** Every package runs its own suite; what the suite downloads gets packaged and the download patched out |

**Recommended and assumed unless you say otherwise:** the AiiDA family follows the repo's existing
`python313` pin rather than the default `python3` (which is 3.14 in the locked nixpkgs).
`aiida-psi4` does `from qcelemental import models`, and that is precisely the import
`pkgs/qcportal/default.nix` documents as broken on 3.14 — qcelemental's `_use_real_if_possible()`
replaces every v1 name with a placeholder there. Pinning keeps all six AiiDA packages buildable and
reuses the `py` binding and the `overlay-python-pin` test that already exist.

### Sources

`fetchPypi` where a release exists, otherwise the `wc/` checkout's HEAD. Read each rev with
`git -C wc/<name> rev-parse HEAD` before writing the derivation — do not copy the SHAs below
without re-checking them.

| Package | Source | Note |
|---|---|---|
| `aiida-core` | `fetchFromGitHub` `aiidateam/aiida-core` @ `e56a906` | `2.10.0.dev0`, unreleased. The ZeroMQ broker (`src/aiida/brokers/zeromq/`, entry point `core.zeromq`) exists only here, and the broker decision depends on it. Version it `2.10.0.dev0-unstable-YYYY-MM-DD` |
| `aiida-cp2k` | `fetchPypi` `2.1.1` | HEAD is exactly the `v2.1.1` tag, so the sdist matches the checkout — **but see the caveat below** |
| `aiida-orca` | `fetchFromGitHub` `ezpzbz/aiida-orca` @ `90e9a3b` | `__version__` is `1.0.0`; newest tag is `v0.7.0`. Version `1.0.0-unstable-YYYY-MM-DD` |
| `aiida-octopus` | `fetchFromGitLab` `octopus-code/aiida-octopus` @ `4903d6b` | **GitLab, not GitHub.** No tags at all, static version `0.1.0` |
| `aiida-psi4` | `fetchFromGitHub` `ltalirz/aiida-psi4` @ `637e6b0` | branch `master`, no tags, `0.1.0a0` |
| `aiida-quantumespresso` | `fetchPypi` `5.0.0` | HEAD is past `v5.0.0` but `__version__` is `5.0.0` |
| `harmonwig` | `fetchFromGitHub` `ispg-group/harmonwig` @ `5ae0c0c` | no tags, `0.1.0a0` |

**aiida-cp2k sdist caveat.** The CP2K VM test and the package's own patched conftest both read
`examples/files/{BASIS_MOLOPT,GTH_POTENTIALS,h2o.xyz}` out of the source tree.
`aiida-cp2k`'s `pyproject.toml` has no `[tool.flit.sdist]` section, so whether `examples/` survives
into the PyPI sdist is not guaranteed. Unpack the sdist and check; if `examples/` is absent, switch
to `fetchFromGitHub` at tag `v2.1.1`.

### cclib comes from its own flake

The commit you pointed at, `cclib/cclib@545fa9b`, carries `flake.nix`, `nix/overlay.nix` and
`nix/cclib.nix`. Two facts make this fit this repo unusually well, and both belong in a comment at
the code:

1. **cclib's flake pins the same two revisions this flake already pins.** Its `flake.lock` has
   nixpkgs `3e41b24abd260e8f71dbe2f5737d24122f972158` — byte for byte the `nixpkgs-qchem` input in
   `flake.nix` — and qchem `faad404d8612268b0f341eaab916d35829b290a5`, the locked `nixos-qchem`.
   So cclib's overlay can be applied straight onto the existing `qchemPkgs` instantiation with no
   new nixpkgs in the closure.
2. **In that nixpkgs, `python3 = python313`** (`pkgs/top-level/all-packages.nix:4722`), not 3.14.
   That matters because `nix/cclib.nix` lists `psi4` as a hard dependency, and cclib's own
   `pyproject.toml` says psi4 is not available on 3.14 yet.

cclib is not cheap: `nix/cclib.nix` promotes the whole `bridges` extra — `psi4`, `pyscf`, `iodata`,
`biopython`, `trexio`, `openbabel-bindings`, `ase`, `pandas`, `pyquante` — into `dependencies`,
where upstream's `pyproject.toml` keeps them optional. Building it means building Psi4. Extending
`qchemPkgs` is what makes that survivable: that set already reproduces NixOS-QChem's own
instantiation, which is the only thing `nix-qchem.cachix.org` was populated from, so Psi4 is
fetched rather than compiled (as long as the invoking user is in `trusted-users` — see the existing
note in `flake.nix`).

#### Flake input

```nix
# cclib is not in nixpkgs and upstream ships its own flake.  Only overlays.default
# is used — a pure  final: prev:  function — so following our inputs is free, and
# both of these already resolve to exactly what cclib's own flake.lock pins.
cclib = {
  url = "github:cclib/cclib/545fa9bdd25af7b6e70d3323d4156791dd54a440";
  inputs.nixpkgs.follows = "nixpkgs-qchem";
  inputs.qchem.follows = "nixos-qchem";
};
```

#### Consequence: harmonwig exists only through the flake

`overlays/default.nix` holds plain `final: prev:` functions and is imported by `default.nix`,
`overlay.nix` and `ci.nix` **without flakes**. It cannot reach a flake input — the same constraint
the header of `tests/qcarchive/vm.nix` already documents for Psi4. So:

- `pkgs/harmonwig/default.nix` takes `cclib ? null` as a defaulted argument. `callPackage` fills it
  from the package set when cclib is present and leaves it `null` when it is not, so evaluation
  succeeds on both paths and `nix-env -f . -qa '*'` (i.e. `just ci-eval`) stays green.
- `meta.broken = cclib == null;` — so `ci.nix` skips it on the bare NUR path rather than failing,
  which is exactly the mechanism the repo already uses. `overlays.harmonwig` therefore yields a
  *working* harmonwig only when composed after cclib's overlay.
- `flake.nix` composes them and exports the real one:

```nix
# qchemPkgs already is NixOS-QChem's own instantiation; cclib's overlay expects
# exactly that (it reads final.qchem.python3.pkgs.psi4) and pins the same revs.
# cclib overrides the top-level python3 rather than pythonPackagesExtensions, so
# this cannot perturb python313Packages and the AiiDA family is unaffected.
harmonwigPkgs = qchemPkgs.extend (
  lib.composeExtensions inputs.cclib.overlays.default (import ./overlays).harmonwig
);
```

then `packages.harmonwig = harmonwigPkgs.harmonwig;` (overriding the broken-marked one that comes
out of `nurAttrs`) and `checks.harmonwig = tests.harmonwig.all;`.

A note worth recording while touching this: the long comment in `flake.nix` (around line 145)
claiming that folding `nixos-qchem.overlays.qchem` into `pkgs'` "would rebuild qcfractal, qcportal
and their whole dependency closure against a different Python package set" is **not true of the
locked NixOS-QChem**. Its `overlay.nix` writes a single namespaced attribute — `cfg.prefix`
defaults to `"qchem"` (`cfg.nix:41`) — and overrides `python3`/`python312`/`python311` only *inside*
that namespace. The rest of that comment (why `nixos-qchem.packages.*` is avoided) still holds.
Correct or delete the stale half rather than leaving it to mislead the next reader.

### New packages

Twenty derivations under `pkgs/<name>/default.nix` plus one fixed-output data derivation, all
following the conventions in `pkgs/qcportal/default.nix` and `pkgs/parsl/default.nix`:
`buildPythonPackage rec { pyproject = true; }`, grouped function arguments with `# build-system` /
`# dependencies` / `# tests` headers, `build-system` + `dependencies` (not
`propagatedBuildInputs`), `pythonImportsCheck`, and a `meta` carrying `description`, `homepage`,
`license`, `maintainers = with maintainers; [ berquist ];`.

#### Tier 1 — aiida-core runtime dependencies missing from nixpkgs

Build in this order; each depends only on earlier ones.

| Package | Notes |
|---|---|
| `archive-path` | pure Python, no deps |
| `disk-objectstore` | AiiDA's file store; deps `click`, `sqlalchemy` |
| `pgsu` | PostgreSQL superuser connection helper; deps `psycopg`, `click` |
| `kiwipy` | build with the `rmq` extra — `aio-pika`, `pamqp`, `shortuuid`, `nest-asyncio` are all in nixpkgs |
| `plumpy` | process state machine; depends on `kiwipy` |
| `upf-to-json` | PyPI name `upf_to_json` |

#### Tier 2 — plugin runtime dependencies missing from nixpkgs

| Package | Needed by |
|---|---|
| `qe-tools` | `aiida-quantumespresso` |
| `aiida-pseudo` | `aiida-quantumespresso`, `aiida-cp2k` |
| `aiida-gaussian-datatypes` | `aiida-cp2k` |
| `cp2k-output-tools` | `aiida-cp2k` |
| `postopus` | `aiida-octopus` — resolve its dependency closure early; it is the least-known package here and the most likely to drag in something else missing |

#### Tier 3 — test-only packages missing from nixpkgs

| Package | Why |
|---|---|
| `pgtest` | Spins up a throwaway PostgreSQL cluster. **Three plugin suites need it** |
| `aiida-testing` | `fetchFromGitHub ltalirz/aiida-testing` @ `6b3c2ae023157e73563630aaf24d8337c348b74b`, the rev `aiida-psi4`'s `setup.json` pins. Provides `mock_code_factory` |
| `sssp-pbe-efficiency-1.3` | Not a Python package: a `fetchurl` fixed-output derivation of the SSSP archive `aiida-cp2k`'s conftest downloads. Read the exact URL and hash out of `aiida-pseudo`'s SSSP family class once tier 2 is built — do not invent it |

#### Tier 4 — the requested packages

`aiida-core`, `aiida-cp2k`, `aiida-orca`, `aiida-octopus`, `aiida-psi4`,
`aiida-quantumespresso`, `harmonwig`.

`aiida-core` specifics:
- `build-system = [ flit-core ]`.
- `meta.mainProgram = "verdi"`. The two console scripts are `verdi` and `runaiida`; neither is named
  after the package, so `lib.getExe` would silently resolve to a nonexistent `$out/bin/aiida-core` —
  the trap `pkgs/qcfractal/default.nix` documents.
- `pythonRelaxDeps` for the bounds the locked nixpkgs sits above: `jedi`, `paramiko`, `wrapt`,
  `click`, `tabulate`, `importlib-metadata`.
- Expose `optional-dependencies.atomic_tools`, because `aiida-quantumespresso` depends on
  `aiida_core[atomic_tools]`. Model the extras block on `pkgs/parsl/default.nix`, including its note
  about why it is not `rec`.
- `pythonImportsCheck = [ "aiida" "aiida.orm" "aiida.engine" "aiida.storage.psql_dos" ]`, **with
  `export HOME="$(mktemp -d)"` before it**. `AiiDAConfigDir.set()` runs at *module import* and
  creates `$HOME/.aiida`, so the import check fails outright against the default
  `/homeless-shelter`.

`harmonwig` specifics: `buildPythonApplication`, `build-system = [ uv-build ]`,
`dependencies = [ ase tqdm cclib ]`, `meta.mainProgram = "harmonwig"`, plus the `cclib ? null` /
`meta.broken` arrangement above.

`aiida-psi4` specifics — it is the awkward one, and the reason belongs in a comment at the code:
its `setup.json` still declares `aiida-core>=1.6.4,<2.0.0`, `sqlalchemy<1.4`, `qcelemental~=0.20.0`
and `setup_requires: ["reentry"]`, all AiiDA-1.x era. But every actual import in `aiida_psi4/` is
AiiDA-2 compatible. There is no `[project]` table at all, so the backend is legacy setuptools driven
by `setup.py` reading `setup.json`. Package it by patching `setup.json` in `postPatch` to drop
`setup_requires`/`reentry_register` (a `setup_requires` entry would otherwise trigger a network
fetch during the build) and to relax the three version pins.

**Every plugin needs `pythonRelaxDeps = [ "aiida-core" ]`.** `buildPythonPackage` runs
`pythonRuntimeDepsCheckHook`, and aiida-core's version here is `2.10.0.dev0` — a pre-release, which
does not satisfy `aiida-core>=2.1,<3` under PEP 440 unless pre-releases are opted in.

### Making the tests run

No `doCheck = false`. Each suite gets what it needs.

**The single most useful fact here:** `aiida.tools.pytest_fixtures` (the modern module) defaults to
`core.sqlite_dos` with no broker and "requires no services to run", whereas the deprecated
`aiida.manage.tests.pytest_fixtures` builds its profile from `config_psql_dos({})` and therefore
**needs a real PostgreSQL**, which it obtains through `pgtest`. Which module a plugin's conftest
names decides whether it needs `pgtest` + `postgresql` in `nativeCheckInputs`.

| Package | Fixture module | What it needs |
|---|---|---|
| `aiida-core` | own conftest | `postgresql` + `pgtest`; broker via ZeroMQ |
| `aiida-cp2k` | legacy | `postgresql`, `pgtest`, `cp2k`, the SSSP archive |
| `aiida-orca` | legacy | `postgresql`, `pgtest`, `pytest-regressions` |
| `aiida-psi4` | legacy + `aiida_testing.mock_code` | `postgresql`, `pgtest`, `aiida-testing` |
| `aiida-octopus` | modern (with a legacy fallback) | `octopus` binary |
| `aiida-quantumespresso` | modern | `pytest-regressions` only |
| `harmonwig` | none | nothing |

#### aiida-core

- `nativeCheckInputs`: `pytestCheckHook`, `pytest-asyncio`, `pytest-timeout`, `pytest-regressions`,
  `pytest-rerunfailures`, `pytest-xdist`, `pytest-benchmark`, `pympler`, `pgtest`, `pg8000`,
  `postgresql`, plus the `atomic_tools` and `rest` extras.
- `pytestFlags = [ "--override-ini=addopts=" ... ]`. Upstream's `addopts` carries
  `--cov-report xml --cov-append --instafail`, which need `pytest-cov`/`pytest-instafail` and write
  outside `$out`.
- **Run against PostgreSQL and ZeroMQ**: `--db-backend psql --broker-backend zmq`. RabbitMQ is the
  one thing that cannot work in a build sandbox; ZeroMQ is in-process, so choosing it is what lets
  the *whole* suite run rather than only the `presto` subset.
- `disabledTestPaths`: `tests/tools/archive/migration`, `tests/sphinxext`, and the SSH transport
  tests.
- `disabledTests`: the `dbimporters` tests that reach COD / ICSD / Materials Project.

#### aiida-cp2k — the download

`conftest.py`'s session-scoped autouse `setup_sssp_pseudos` shells out to
`aiida-pseudo install sssp -p efficiency -x PBE -v 1.3`, which downloads from Materials Cloud.
Package the archive and patch the call:

1. A `fetchurl` derivation for the SSSP 1.3 PBE efficiency archive and its metadata JSON.
2. `postPatch` rewrites the `subprocess.run` list to the local-archive form of the same command.
3. The same `postPatch` replaces the hardcoded `/opt/conda/envs/cp2k/bin/cp2k.psmp` in the
   `cp2k_code` fixture with `${cp2k}/bin/cp2k.psmp` and drops the `conda activate` `prepend_text`.
4. `nativeCheckInputs = [ pytestCheckHook pgtest postgresql cp2k aiida-pseudo ]`.

`pytestFlags = [ "test" ]`, restricted to the unit-test directory. This is a scoping decision, not a
disabling one: `python_files = "test_*.py example_*.py"` also collects `examples/`, and those submit
real CP2K jobs through a running AiiDA daemon. **Those examples become the VM plugin round trip
instead.**

#### aiida-psi4 — the git-pinned test dependency

Package `aiida-testing` at the pinned rev as tier 3. **This is the highest-risk item in the plan.**
`aiida-testing` at a 2021 rev against aiida-core 2.10 may simply not import. If it cannot be made to
work, that is the one place to come back and ask rather than quietly reaching for
`doCheck = false`.

#### The rest

- `aiida-orca`: unit tests use `aiida_local_code_factory('orca.orca', '/bin/bash')`, so no ORCA
  binary is needed.
- `aiida-octopus`: its conftest does `subprocess.run(["which","octopus"])` and raises if absent.
- `aiida-quantumespresso`: modern fixtures, so SQLite and no services.
- `harmonwig`: pure unit tests. Its `filterwarnings = ["error"]` turns any new ASE/NumPy
  deprecation into a build failure.
- `cclib`: comes from the upstream flake, which already carries its own `disabledTests`.

### Overlays and re-exports

Two new named overlays in `overlays/default.nix`, alongside `dotdrop` and `qcfractal`. The `aiida`
one composes automatically. The `harmonwig` one only produces a working package when cclib's overlay
is applied first.

`default.nix` adds the tier-4 AiiDA names to the existing `inherit (py) ...` list, and `harmonwig`
to the `inherit (pkgs') dotdrop;` line. Tier-1 through tier-3 packages stay reachable through
`python313Packages` but are **not** re-exported as top-level NUR attributes.

### NixOS module: `nixos-modules/aiida.nix`

Options under `services.aiida`, following `nixos-modules/qcfractal-server.nix`. Four things make
this module genuinely different from the QCFractal ones, and each needs its explanation at the code:

1. **`verdi` must come from an environment that also contains the plugins.** Plugins are found
   through Python entry points, and `aiida/engine/daemon/client.py` resolves the binary with
   `shutil.which('verdi')` and then spawns `verdi daemon worker` and `verdi daemon broker` as circus
   subprocesses. So the module builds
   `pythonEnv = cfg.package.pythonModule.withPackages (_: [ cfg.package ] ++ cfg.plugins)` and uses
   `lib.getExe' pythonEnv "verdi"` — **not** `lib.getExe cfg.package`.
2. **Config location.** AiiDA reads `AIIDA_PATH` and appends `.aiida`, so the unit sets
   `AIIDA_PATH = cfg.stateDir`.
3. **Three units, mirroring the server module**: `aiida-init` (oneshot, guarded by
   `verdi profile show`), `aiida-storage-migrate` (defined always, `wantedBy` only under
   `autoMigrate`), `aiida-daemon` (`Type = "forking"`, `PIDFile` = the circus pid file).
4. **PostgreSQL.** Unlike QCFractal, `verdi profile setup core.psql_dos` does *not* create the
   database, so this module **does** use `services.postgresql.ensureDatabases`.

Assertions to carry, each with an `assertFails` eval test: peer-auth user mismatch;
`createLocally = false` with a socket host; `broker = "core.rabbitmq"` without
`services.rabbitmq.enable`; `workers < 1`.

### Tests

`tests/aiida/default.nix` copies the harness from `tests/qcarchive/default.nix` verbatim — these
helpers are deliberately not factored out in this repo. `tests/aiida/vm.nix` gets four tests:
`daemon-local-db`, `workchain-arithmetic`, `plugin-cp2k` (the real plugin round trip, and the home
for the `examples/` the package's own checkPhase does not collect), `daemon-rabbitmq`.
`tests/harmonwig/default.nix` gets `metadata` and `cli-errors`, modelled on
`tests/dotdrop/default.nix`.

### Documentation

`AGENTS.md` (new rows in "Where the explanations live", AiiDA in the three-edits section, the stale
`qchemPkgs` comment corrected), `README.md`, `tests/AGENTS.md`.
`docs/aiida-profile-bootstrapping.md` **only** if the profile setup turns out to need a manual step
the module cannot declare. Do not write it speculatively.

### Risks worth knowing before starting

- **`aiida-testing` at a 2021 rev against aiida-core 2.10.**
- **cclib pulls in Psi4.** Cached, a download; uncached, hours.
- **`postopus`** is the one tier-2 package whose dependency closure could not be inspected offline.
- **Version-constraint churn.** The locked nixpkgs sits above seven of aiida-core's upper bounds.
- **Scope.** Twenty-one derivations, one module, three test directories.

---

## Out-of-band

Nothing was run with the `!` prefix, so there is nothing recoverable from the transcript.

Two things did change under the working tree from outside the session:

- The `wc/` checkouts gained **five new projects** during the session — `DBSTEP`, `RMG-Py`,
  `QMzyme`, `aqme`, `ccreg`. None of them is covered by the plan above, which was written against
  the eight that were there at the start. See Follow-ups.
- `wc/cclib` was added between the rejected and the approved `ExitPlanMode`, as the reply said it
  would be.

## Changes

Nothing was committed — per the repo convention I stage and draft, the user commits. `git` is not
on `PATH` inside this sandbox, so even staging had to be handed back (see below).

**New packages** (`pkgs/<name>/default.nix`):

| Package | Why it exists |
|---|---|
| `archive-path`, `disk-objectstore`, `pgsu`, `pytray`, `kiwipy`, `plumpy`, `upf-to-json` | aiida-core runtime deps, none in nixpkgs. `pytray` was not in the plan — it turned up as a transitive requirement of kiwipy's `rmq` extra |
| `pgtest` | throwaway PostgreSQL cluster; three plugin suites need it |
| `qe-tools`, `aiida-pseudo`, `aiida-gaussian-datatypes`, `cp2k-output-tools`, `postopus` | plugin runtime deps |
| `aiida-testing` | git-pinned fork supplying aiida-psi4's `mock_code_factory` |
| `aiida-core` | the centrepiece; `meta.mainProgram = "verdi"` |
| `aiida-cp2k`, `aiida-orca`, `aiida-octopus`, `aiida-psi4`, `aiida-quantumespresso` | the five plugins |
| `harmonwig` | standalone CLI, `cclib ? null` + `meta.broken` so the bare NUR path stays green |

**New module and tests**: `nixos-modules/aiida.nix` (~760 lines, `services.aiida.*`),
`tests/aiida/default.nix` (29 eval tests), `tests/aiida/vm.nix` (4 VM tests),
`tests/harmonwig/default.nix` (2 tests).

**Wiring**: `overlays/default.nix` (two new overlays), `default.nix`, `nixos-modules/default.nix`,
`flake.nix` (cclib input, `harmonwigPkgs`, `aiidaVmTests`, `harmonwigTests`, six new checks),
`tests/default.nix`, `Justfile` (`aiida-eval-tests`, `harmonwig-tests`; `vm-test-interactive` now
takes a suite argument), `scripts/no-daemon-check.sh` (both eval suites, both VM suites),
`.gitignore` (`/wc/`).

**Docs**: `AGENTS.md`, `README.md`, `tests/AGENTS.md`.

## Outcome

Green, within the limits of a sandbox that cannot build anything:

- `tests/aiida` — **29/29 PASS**; `tests/qcarchive` — **34/34 PASS**, unchanged.
- All four AiiDA VM tests, both harmonwig tests, and every package except harmonwig instantiate
  against the nixpkgs pinned in `flake.lock`.
- Every tracked `.nix` file parses; `scripts/no-daemon-check.sh` passes `bash -n`.
- `ci.nix`'s `cacheOutputs` picks up all six public AiiDA packages and correctly excludes
  harmonwig as broken.

### What was rejected, and why

- **Moving the AiiDA family to `python312`.** nixpkgs' pymatgen carries
  `disabled = pythonAtLeast "3.13"`, which throws at *evaluation*, and I started re-pinning the
  whole family to escape it. The user stopped that:
  `pymatgen.overridePythonAttrs (_: { disabled = false; })` instantiates and evaluates its whole
  closure on 3.13 unchanged. The override sits at aiida-core's `callPackage` site, **not** in the
  `pythonPackagesExtensions`, so taking `overlays.aiida` cannot silently change pymatgen for a
  consumer — `aiida-overlay-pymatgen-override-is-local` asserts exactly that.
- **`fetchPypi` for `aiida-quantumespresso`**, which the plan called for. Its
  `[tool.hatch.build.targets.sdist]` excludes `tests/` outright, so the sdist cannot run its own
  suite. `fetchFromGitHub` at tag `v5.0.0` is the same tree. Same conclusion as `aiida-cp2k`, but a
  sharper reason: there the sdist question was open, here it is settled in the metadata.
- **`core.arithmetic.add_multiply` for the VM round trip**, which the plan and the
  `AskUserQuestion` answer both named. It is a process *function*, and AiiDA can only `run` those in
  the caller's process, never `submit` them — so it would have exercised nothing about the daemon.
  `core.arithmetic.multiply_add` (a `WorkChain`) is used instead: submitted, picked up by a worker,
  and it submits an `ArithmeticAddCalculation` of its own, so one pass covers broker, worker,
  scheduler and local transport.
- **Packaging the SSSP archive for aiida-cp2k**, which the plan specified in some detail. Nothing
  under `test/` uses an SSSP family — the downloading fixture exists for the `examples/`, which
  that package's checkPhase deliberately does not collect. A packaged archive would have been
  fetched and never read. `postPatch` swaps `subprocess.run(` for `list(`, which neutralises the
  download without deleting the fixture. If the examples are ever brought into checkPhase, the
  comment at that code says where the offline `aiida-pseudo install family` would go.
- **An embedded Python heredoc in aiida-cp2k's `postPatch`.** Indentation inside `<<'EOF'` nested in
  a Nix indented string was fragile, and the follow-up attempt tripped nixfmt on `''\'''` quote
  escaping. Three `substituteInPlace --replace-fail` calls do the same job, matching only inner
  Python string contents that contain no single quotes.
- **`builtins.readFile` on a unit's `ExecStart`** in the eval suite. That is import-from-derivation,
  which builds the script and defeats the whole point of a suite that reports PASS/FAIL without a
  daemon. `writeShellScript`'s `.text` attribute instead, matching the qcarchive suite.

### Corrections made against the plan and the pre-compaction summary

- **`aiida-orca`'s owner is `ezpzbz`, not `pzarabadip`.** `pyproject.toml`'s `Home` URL says
  `pzarabadip`; the checkout's git remote says `ezpzbz`, and that is where the pinned SHA lives.
  The derivation follows the remote.
- **The `qchemPkgs` comment in `flake.nix` was half wrong** and is now corrected in place.
  NixOS-QChem's `overlay.nix` writes exactly one attribute, namespaced under `cfg.prefix`
  (`"qchem"`), and the `python3` it overrides is `qchem.python3` — so folding it into `pkgs'` would
  *not* rebuild the QCArchive closure. The cache-hash reason for keeping it separate is real and is
  what the comment now says.
- **`aiida-psi4`'s `tests/test_data.py` imports `ValidationError` from `pydantic.error_wrappers`**,
  the pydantic-1 location, which is a raising migration stub under the pydantic 2 aiida-core pulls
  in. But qcelemental's v1 models validate through `pydantic.v1`, so the exception the test wants
  really is the v1 one — `postPatch` rewrites the import to `pydantic.v1.error_wrappers`.

### Not done

- **Five `lib.fakeHash` values remain** — the plugin sources (`aiida-cp2k`, `aiida-orca`,
  `aiida-octopus`, `aiida-psi4`, `aiida-quantumespresso`). Everything else carries a real hash,
  recovered offline by reading the sdist sha256 hex out of `wc/*/uv.lock` and converting with
  `nix-hash --to-sri --type sha256`.
- **No package has ever been built.** No nix-daemon and no network in this sandbox.
- **`just fmt` / `just lint` / `just hooks` / `shellcheck` have not run.** None of `nixfmt`,
  `statix`, `deadnix`, `prek`, `shellcheck`, `just` or `git` is on `PATH` here. A PostToolUse hook
  did format the Nix files as they were written.
- `docs/aiida-profile-bootstrapping.md` was deliberately not written: the module declares the whole
  profile, so there is no manual step to document.

### Failure modes expected on the first real build

Both are flagged in comments at the code rather than worked around:

- **`aiida-octopus`** asserts a converged Octopus energy and twelve force components to nine
  significant figures against numbers recorded from one particular upstream build. A numerical
  mismatch there is version skew, and the fix is a `disabledTests` entry quoting the observed
  numbers — not disabling the suite.
- **`aiida-quantumespresso`** needs `xmlschema` relaxed from `~=2.0` to the locked nixpkgs' 4.3.1.
  This is the only relaxation in the repo that crosses two majors of a library the package really
  uses: it builds an `XMLSchema` and validates pw.x output against it.

## Follow-ups

- **Fill the five `lib.fakeHash` values**, then work up the tiers with `just build <name>`. A
  tier-1 failure invalidates everything above it, so do not batch.
- **Confirm two revs I could not check.** `aiida-orca` @ `90e9a3b…` and `aiida-octopus` @
  `4903d6b…` came from the plan, not from `git rev-parse`: these checkouts use the reftable format
  and there is no `git` in this sandbox.
- **Run `just fmt && just lint && just hooks`**, and `shellcheck scripts/no-daemon-check.sh`.
- **Five new `wc/` checkouts arrived during the session** — `DBSTEP`, `RMG-Py`, `QMzyme`, `aqme`,
  `ccreg`. The original ask was "each of the projects in the wc directory", so these are the
  obvious next batch; none has been looked at.
- **Proposal — make `scripts/no-daemon-check.sh` work in the sandbox it exists for.** It is the
  repo's designated no-daemon entry point, but it calls `git ls-files` for the parse step and `jq`
  for the verdict parsing, and neither is on `PATH` in the Claude Code sandbox. Consequence: the
  `nix-instantiate --store "$TMPDIR/…"` preamble was retyped by hand **35 times** this session,
  which is exactly what the script was written to prevent. Suggested fix: fall back to
  `find . -name '*.nix' -not -path './wc/*'` when `git` is missing, and resolve `jq` and `nix` from
  known store paths when they are not on `PATH`.
- **Proposal — a `just vm-test-aiida <name>` shorthand**, or teach `vm-test` the suite prefix. The
  flake names the AiiDA checks `vm-aiida-*`, so `just vm-test aiida-daemon-local-db` reads oddly
  next to `just vm-test-interactive daemon-local-db aiida`.
