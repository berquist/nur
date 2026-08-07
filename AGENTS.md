# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

berquist's personal [NUR](https://github.com/nix-community/NUR) repository, built from
`nur-packages-template`. Beyond the template scaffolding it holds two unrelated bodies of work:

- the **QCArchive/QCFractal ecosystem** — Python packages (`qcportal`, `qcfractal`,
  `qcfractalcompute`, `qcarchivetesting`, `parsl`) plus two NixOS service modules for running a
  QCFractal server and compute worker. This is the bulk of the repo, and everything below about
  the python313 pin, `nixpkgs-qchem` and the VM tests is about it.
- **dotdrop** — a standalone dotfile-manager CLI, not in nixpkgs. It shares nothing with the
  above and is deliberately kept separate: its own overlay (`overlays.dotdrop`), its own test
  subdirectory (`tests/dotdrop/`), and the default `python3` rather than the 3.13 pin.

The `nixos-qchem` flake input supplies quantum-chemistry programs (Psi4, CFOUR, NWChem, …) as
`pkgs.qchem.*`; it is re-exported as `overlays.qchem`. `overlays.default` composes it with
every overlay in `overlays/`, so adding an overlay there needs no second edit in `flake.nix`.

### Psi4, and why `nixpkgs-qchem` exists

`nix-qchem.cachix.org` is populated by NixOS-QChem's Hydra, which builds against the nixpkgs
pinned in *its* `flake.lock` with the config *its* flake sets. Hitting that cache means
reproducing both, so `flake.nix` carries a third input, `nixpkgs-qchem`, pinned by hand to the
revision NixOS-QChem pins, and instantiates it with `overlays.qchem`, `allowUnfree` and
`qchem-config { allowEnv = false; optAVX = true; }`. Deviate on any of those and Psi4's whole
closure (CheMPS2, adcc, libint, …) compiles from source. **Bump `nixpkgs-qchem` whenever
`nixos-qchem` is bumped** — the command to read the target revision is in the comment on the
input.

Two traps that look like obvious cleanups but are not:

- **Do not use `nixos-qchem.packages.${system}.psi4`.** That output is a `filterAttrs` over the
  entire `qchem` set, so selecting one package forces the predicate for *every* package. The
  predicate guards with `builtins.tryEval`, which catches only `throw` and `assert` — not plain
  eval errors such as `called with unexpected arguments 'blas', 'lapack' and 'scalapack'`, which
  is exactly how their `nwchem` override breaks against a newer nixpkgs. One broken package
  anywhere in NixOS-QChem then takes down our whole `checks` output. Select `qchem.psi4` from our
  own instantiation instead; it forces only Psi4.
- **`nixos-qchem.inputs.nixpkgs.follows = "nixpkgs"` is fine and intended**, but only because
  nothing here uses that input's instantiated outputs — just `overlays.qchem` (a pure function)
  and `cfg.nix` (a file). If anything ever does consume its `packages`/`legacyPackages`, the
  `follows` has to go, or the cache is lost again.

Separately: `nixConfig.extra-substituters` is ignored unless the invoking user is in
`trusted-users`. Without that, `nix flake check` silently builds Psi4 from source no matter how
correct the pinning is — check for `warning: ignoring untrusted flake configuration setting` in
the output before blaming the derivation hashes.

See `docs/nwchem-as-a-test-program.md` for why the VM tests use Psi4 rather than the
nixpkgs-native NWChem.

## Commands

**The `Justfile` is the source of truth for what CI runs.** `.github/workflows/build.yml`
calls the `ci-*` recipes rather than spelling the commands out, so `just ci <channel>`
reproduces one matrix leg end-to-end locally. Add CI logic there, not to the workflow.

```sh
just                      # list every recipe

just ci                   # one channel's full sequence (default: nixpkgs-unstable)
just ci nixos-26.05       # a specific channel
just ci-matrix            # all three channels the workflow matrix covers

just build qcfractal      # single package, NUR style (via default.nix, overlays applied)
nix build .#qcfractal     # single package, flake style

just check                # everything: eval tests, all six VM tests, pre-commit hooks
```

The three `ci-*` recipes evaluate against the **ambient** `NIX_PATH` — GitHub Actions sets
it from the workflow matrix, and the `ci` wrapper sets it locally. That is the only copy of
each command.

### CppNix and Lix

The recipes run under both. The one thing that reliably breaks across the two is anything
that parses `nix --version`: CppNix says `nix (Nix) 2.34.8`, Lix says
`nix (Lix, like Nix) 2.x.y`. **Do not add anything that parses it.**

That is exactly why `ci-build` no longer uses `nix-build-uncached`, which the NUR template
shipped. It `Sscanf`s the literal format `nix (Nix) %d.%d.%d` and aborts with
`Failed to get nix version` on Lix before doing any work — a property of the tool, not the
environment, so switching CI to Lix would break it there too. It bought nothing while the
cachix step is disabled by its `<YOUR_CACHIX_NAME>` guard, since skipping paths already in
*your* cache is its whole purpose. Revisit if cachix is turned on.

`-L` is on the recipes that use the **new** CLI (`nix flake check`, `nix build`), so a whole
run can be redirected to a file. Classic `nix-build` rejects `-L` outright
(`error: unrecognised flag '-L'`) but streams builder output by default, so the `nix-build`
recipes need nothing.

Tooling (`just`, `nixfmt`, `statix`, `deadnix`, `prek`, `jq`) comes from the
devShell: `nix develop`, or direnv. Entering it also generates `.pre-commit-config.yaml`
from the `pre-commit.settings.hooks` block in `flake.nix` — that block is the source of
truth, the generated file is gitignored, and `just hooks` runs the hooks over the tree.

### Non-VM tests

`tests/default.nix` is a dispatcher over one subdirectory per subject; see `tests/CLAUDE.md`.

```sh
just tests                                    # every non-VM suite

just eval-tests                               # QCFractal module eval tests only
nix-build tests -A qcarchive.server-defaults  # one of them
nix build .#checks.x86_64-linux.eval

just dotdrop-tests                            # dotdrop integration tests
nix-build tests -A dotdrop.roundtrip          # one of them
nix build .#checks.x86_64-linux.dotdrop
```

The qcarchive tests are pure evaluation against stubbed packages and so are fast. The dotdrop
tests need no VM but do build the real package and run upstream's `tests-ng` scripts against it,
so they are not free.

### VM integration tests (need KVM and real, buildable packages)

```sh
just vm-test server-local-db        # also: server-open-firewall, server-remote-db,
                                    # compute-connects, compute-authenticated,
                                    # compute-singlepoint
just vm-test-interactive server-local-db
```

Nix files are formatted with `nixfmt`; match the surrounding layout. `just fmt` formats
every tracked file, `just lint` runs statix and deadnix.

Two deliberate lint exemptions, both of which look like oversights:

- **`trim-trailing-whitespace` excludes `*.patch`.** Trailing whitespace is significant in a
  unified diff — a blank context line is a single space — so stripping it makes the hunk fail
  to apply. Letting the hook touch `pkgs/parsl/conftest.patch` breaks the parsl build.
- **`statix.toml` disables `repeated_keys` (W20).** It wants the flat, dotted
  `systemd.tmpfiles.rules = …; systemd.services.foo = …;` style collapsed into one nested
  block. That style is how NixOS config is normally written here, and collapsing the server
  module's three units — or `tests/qcarchive/vm.nix`'s per-node `database.*` / `executor.*`
  settings —
  would make both harder to read.

## Architecture

### Two entry points, one source of truth

`default.nix` is the NUR entry point and the canonical package list. `flake.nix` and
`overlay.nix` both derive from it:

- `flake.nix` → `legacyPackages` = `import ./default.nix`; `packages` = the derivations
  filtered out of that.
- `overlay.nix` → the same attrset minus the *reserved* keys.

`flake.nix` is a **flake-parts** flake: `systems` comes from `nix-systems/default`, per-system
outputs live in `perSystem`, and `nixosModules` / `overlays` sit in the system-agnostic `flake`
block. Note that `perSystem`'s `pkgs` argument is the *un-overlaid* nixpkgs — `default.nix`
applies the overlays itself, so `legacyPackages` must use it as-is. The separate `pkgs'` in the
`let` is the overlaid set, and is what the eval and VM tests need.

**Reserved keys** (`lib`, `overlays`, `nixosModules`, `homeModules`, `darwinModules`,
`flakeModules`) are attrs in `default.nix` that must not be lifted into a nixpkgs overlay. The
`isReserved` predicate is duplicated in both `overlay.nix` and `ci.nix` — adding a new reserved
key means editing both.

### Python packages go through the overlay, not `callPackage`

`overlays/default.nix` injects every QCArchive Python package into `pythonPackagesExtensions`,
so they land in *every* `pythonX.pkgs` set, **and** re-exports them as top-level `pkgs.*`
aliases. `default.nix` then applies that overlay to a local `pkgs'` and re-exports the packages
with `inherit (pkgs'.python313Packages) …`. All three routes are the *same* derivation, so
`nix-build -A qcfractal`, `pkgs.qcfractal`, and `python313.withPackages (p: [ p.qcfractal ])`
produce identical store paths. The `overlay-python-pin` eval test asserts exactly that.

### Why python313 and not python3

The interpreter is pinned, in two places that must agree: `py` in `default.nix` and the
top-level `inherit` in `overlays/default.nix`.

qcportal 0.65 is built on pydantic v1 throughout, and **qcelemental refuses to provide
QCSchema v1 on Python 3.14+**: `_use_real_if_possible()` in `qcelemental/models/v1/__init__.py`
returns `False` unconditionally for `sys.version_info >= (3, 14)`, replacing every v1 name with
a `_make_placeholder(...)` class. One of those names is `Array`, which `qcportal`'s
`dataset_models.py` subscripts as `index: Array[str]`. The placeholder has an ordinary
metaclass, so pydantic v1 resolving that annotation dies with

```
TypeError: type 'Array' is not subscriptable
```

and `pythonImportsCheck` turns it into a build failure. This is upstream's deliberate choice,
not a packaging bug — its own message says *"run on Python < 3.14 or migrate to
qcelemental.models.v2"*. There is nothing to patch and no release to move to: 0.65 is the
newest (`v0.7.x` are from 2019), and QCFractal's pydantic-v2 migration is merged on `main` but
unreleased.

nixpkgs-unstable moved `python3` to 3.14, which is what broke CI. Following the default
interpreter would leave this repo shipping nothing at all on unstable, and would take every VM
test in `nix flake check` down with it the moment `flake.lock` is bumped past the switch — the
tests build the real `qcfractal`. Hence the pin.

The four packages that pull in qcportal *also* carry `meta.broken = pythonAtLeast "3.14"`.
That is not redundant with the pin: it is what keeps `python314Packages.qcfractal` from failing
with an opaque `TypeError`, and what `ci.nix`'s filter acts on. `meta.broken` does **not**
propagate to dependents, and a broken dependency throws at *evaluation* time when a dependent is
built, so each of the four needs its own marking. `parsl` does not touch qcportal and is not
marked.

**Revisit condition:** drop both the pin and the `broken` flags once upstream releases the
pydantic-v2 migration.

Two things verified rather than assumed, worth not re-deriving: `ci.nix`'s `isBuildable` reads
`meta.broken` lazily and never forces `outPath`, and `nix-env -qa --meta --xml --drv-path`
*silently omits* broken packages rather than erroring — so the workflow's eval step tolerates
the marking.

The top-level aliases are load-bearing, not a convenience: both NixOS modules use
`lib.mkPackageOption pkgs "qcfractal"` / `"qcfractalcompute"`, which resolves against the top
level of `pkgs`. Dropping them makes every consumer of `overlays.qcfractal` fail with
"qcfractal cannot be found in pkgs".

Adding a new Python package therefore requires **three** edits: the `pself.callPackage` line and
the top-level `inherit (final.python313Packages)` list, both in `overlays/default.nix`, plus the
`inherit (py)` list in `default.nix`. Inside a package derivation, dependencies on sibling
packages resolve automatically through the extended package-set fixpoint (`pself`) — do not
thread them in manually.

Packages driven by the modules need `meta.mainProgram`: the modules launch them with
`lib.getExe`, which silently falls back to the *package* name, and neither console script is
named after its package (`qcfractal` → `qcfractal-server`, `qcfractalcompute` →
`qcfractal-compute-manager`).

Non-Python packages are plain `pkgs'.callPackage` calls in `default.nix` (see
`example-package`).

### dotdrop

None of the above applies to it. It is a Python *application*, not a library anything imports,
so it does not go through `pythonPackagesExtensions`: `overlays/default.nix` has a separate
`dotdrop` overlay that does one `final.python3Packages.callPackage`, and `default.nix` picks it
back up with `inherit (pkgs') dotdrop;` so that `pkgs.dotdrop` and `nix-build -A dotdrop` are
the same derivation. It follows the default `python3` — it has no pydantic-v1 constraint and
works on 3.14.

The one non-obvious thing in `pkgs/dotdrop/default.nix` is `makeWrapperArgs`. dotdrop shells out
to two Unix tools and refuses to run without them, and neither is a Python dependency, so
nothing in `pyproject.toml` declares them:

- `utils.dependencies_met()`, called from `main()` on **every** invocation, does
  `shutil.which('file')` and raises `UnmetDependency` if that comes back empty;
- `Settings` validates config's `diff_command` (default `diff -r -u {0} {1}`) through
  `utils.is_bin_in_path()`, so loading any config at all needs `diff`.

Upstream's own suites never catch this — they run in a dev environment where both are already on
`PATH`. `tests/dotdrop/`'s `tests-ng` check keeps `file` and `diffutils` out of its own `PATH`
precisely so that the wrapper is what has to supply them.

### What CI builds

`ci.nix` flattens `default.nix` and filters by `meta.broken`, `meta.license.free`, and
`preferLocalBuild`. A package that cannot build **must** carry `meta.broken = true;` or CI and
cache population fail.

### NixOS modules

See `nixos-modules/CLAUDE.md` (loads automatically when working under `nixos-modules/`) for
module conventions, the config-YAML/secrets pattern, the three-systemd-units design, and the
QCEngine/PYTHONPATH discovery gotcha.

### Tests

See `tests/CLAUDE.md` (loads automatically when working under `tests/`) for the
subdirectory-per-subject layout and what each suite covers.

### Known packaging quirks

- `qcarchivetesting` declares `qcfractal`/`qcfractalcompute` in `Requires-Dist`, which would
  create a derivation cycle. It carries `dontCheckRuntimeDeps = true` and only depends on
  `qcportal`; consumers get the rest from their own `withPackages`/devShell.
- `parsl` is built from the sdist (the wheel omits `version.py` and `requirements.txt`) and
  patches `conftest.py` for pytest 9 (upstream Parsl#4051). Only `parsl/tests/unit` is run.
- `qcfractalcompute` patches `run_scripts/qcengine_compute.py` to redirect into `StringIO`
  rather than `None`. `redirect_stdout(None)` sets `sys.stdout` to None, and since QCEngine
  0.50.0 that block imports psi4 in-process, which imports adcc, which reads
  `sys.stdout.isatty()` at class-definition time — so every claimed task fails with
  `'NoneType' object has no attribute 'isatty'`. 0.65 is the newest release, so there is
  nothing to upgrade to; see the patch header. Coupled to the `PYTHONPATH` change in
  `nixos-modules/qcfractal-compute.nix` — that is what makes adcc importable in the first
  place, and so what exposed this.

## Working inside the Claude Code sandbox

The sandbox blocks `socket(AF_UNIX)`, so `nix` cannot reach the nix-daemon — nothing can be
built or realised, and `nix flake check` / `nix-build` are unavailable; ask the user to run
those. Evaluation is still possible. See the `no-daemon-check` skill for the mechanics,
including `just check-no-daemon` and the four traps it works around — among them that
`NIX_PATH` must come from `flake.lock`, not the flake registry, or default-interpreter breakage
is invisible.

## Template leftovers

`README.md` is still mostly the upstream template, and
`.github/workflows/build.yml` still contains the `<YOUR_REPO_NAME>` / `<YOUR_CACHIX_NAME>`
placeholders, which keep the cachix and NUR-update steps disabled by their `if:` guards.
