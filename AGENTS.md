# AGENTS.md

Guidance for working in this repository.

## What this is

berquist's personal [NUR](https://github.com/nix-community/NUR) repository, built from
`nur-packages-template`. It holds five unrelated bodies of work:

- the **QCArchive/QCFractal ecosystem** — Python packages (`qcportal`, `qcfractal`,
  `qcfractalcompute`, `qcarchivetesting`, `parsl`) plus two NixOS service modules.
- the **AiiDA ecosystem** — `aiida-core`, six quantum chemistry plugins (`aiida-cp2k`,
  `aiida-gaussian`, `aiida-orca`, `aiida-octopus`, `aiida-psi4`, `aiida-quantumespresso`), the
  fifteen-odd dependencies of both that nixpkgs does not carry, and one NixOS service module.
  Together with QCArchive this is the bulk of the repo. It shares the `python313` pin with
  QCArchive and nothing else; the two overlays are separate so that a consumer can take one
  without the other's closure.
- the **cheminformatics family** — `morfeus-ml`, `qmzyme`, `dbstep`, `aqme`, `ccreg`,
  `digichem-core`, plus the nine dependencies of those that nixpkgs lacks (`mdanalysis`,
  `griddataformats`, `mda-xdrlib`, `mrcfile`, `basis-set-exchange`, `colour-science`,
  `configurables`, `openprattle`, `lwreg`). Two overlays rather than one, split on whether the
  package needs cclib — see the cclib split below.
- **dotdrop** — a standalone dotfile-manager CLI, not in nixpkgs. It shares nothing with the
  above and is deliberately kept separate: its own overlay, its own test subdirectory, and the
  default `python3` rather than the 3.13 pin.
- **harmonwig** — likewise a standalone CLI.

### The cclib split

cclib is in neither nixpkgs nor NixOS-QChem and upstream ships its own flake, so that is where it
comes from. `overlays/` holds plain `final: prev:` functions and is imported **without flakes** by
`default.nix`, `overlay.nix` and `ci.nix`, so it cannot reach a flake input. Six packages need
cclib and each takes it as a defaulted `cclib ? null` argument:

| Package | Where it lives | Buildable through |
|---|---|---|
| `harmonwig` | `overlays.harmonwig` | the flake only |
| `dbstep`, `aqme`, `ccreg`, `digichem-core` | `overlays.cheminformatics-cclib` | the flake only |
| `aiida-gaussian` | `overlays.aiida` | **neither**, today |
| `qmzyme` | `overlays.cheminformatics` | both — its cclib use is test-only and lazy |

The first five are `meta.broken` on the NUR path and replaced in `flake.nix`'s `packages` by the
ones from `cclibPkgs`. `aiida-gaussian` is broken everywhere: a plugin must come from the same
package set as its `aiida-core`, and putting the `aiida` overlay into `cclibPkgs` would rebuild
that whole closure against NixOS-QChem's nixpkgs rather than ours.

Note that cclib's overlay overrides the **top-level `python3` attribute** and nothing else, so
`final.python3.pkgs` is the only set that has it. Two traps follow, and both are silent — a
`callPackage` whose `cclib` argument is defaulted just leaves it `null`:

- `final.python313Packages`, which every other family here uses, is a different set that never
  sees cclib. So `overlays.cheminformatics-cclib` and `overlays.harmonwig` are top-level
  `callPackage`s rather than `pythonPackagesExtensions` members.
- **`final.python3Packages` is not `final.python3.pkgs`.** nixpkgs defines
  `python3Packages = dontRecurseIntoAttrs python314Packages` — an alias to the *versioned* set,
  which cclib's overlay does not touch. Spelling it `python3Packages` yields a package that is
  `meta.broken` even on the flake path, with nothing to say so. Always `final.python3.pkgs`.

The `nixos-qchem` flake input supplies quantum-chemistry programs as `pkgs.qchem.*` and is
re-exported as `overlays.qchem`.

## Where the explanations live

Every non-obvious decision here is commented **at the code it governs**, because that is where
it will be read. Do not copy those explanations into this file; add a pointer instead.

| Question | Read |
|---|---|
| Why `python313` and not `python3`? What is `meta.broken` protecting? | `pkgs/qcportal/default.nix` (`meta`), `default.nix` |
| Why is Psi4 taken from a hand-pinned `nixpkgs-qchem`, and why not `nixos-qchem.packages.*`? | `flake.nix` (the `nixpkgs-qchem` input, and `qchemPkgs` in `perSystem`) |
| Why does the compute unit set `PYTHONPATH`, and why per-program envs? | `nixos-modules/qcfractal-compute.nix` |
| Why three systemd units on the server, and why is `upgrade-db` manual by default? | `nixos-modules/qcfractal-server.nix` |
| Why no `nix-build-uncached`, and what breaks between CppNix and Lix? | `Justfile` (the note above `ci-build`) |
| Why is `repeated_keys` disabled? Why does the whitespace hook skip `*.patch`? | `statix.toml`, `flake.nix` |
| Why does `qcfractalcompute` carry a patch? Why is `parsl` built from the sdist? | the respective `pkgs/*/default.nix` |
| How do I check anything from inside the Claude Code sandbox? | the `no-daemon-check` skill, `scripts/no-daemon-check.sh` |
| How does a worker get an account and a password? Why `qcfractal-manage`? | `docs/bootstrapping-worker-credentials.md` |
| Why does `verdi` come from a `withPackages` env instead of `lib.getExe cfg.package`? | `nixos-modules/aiida.nix` (`pythonEnv`) |
| Why does the AiiDA module ensure the *database* when the QCFractal one deliberately does not? | `nixos-modules/aiida.nix` (`services.postgresql`) |
| Why `Type = "forking"` for the daemon, and where does that pid file come from? | `nixos-modules/aiida.nix` (`systemd.services.aiida-daemon`) |
| Why is `core.zeromq` the default broker, and why is aiida-core taken from git? | `pkgs/aiida-core/default.nix` (the `src` comment) |
| Why is nixpkgs' `pymatgen` interpreter gate lifted, and why is it a `let` binding? | `overlays/default.nix` (the `pymatgen` binding in the `aiida` extension) |
| Why does `aiida-psi4` patch `setup.json`? What is `reentry` doing there? | `pkgs/aiida-psi4/default.nix` (`postPatch`) |
| Why does every AiiDA package set `HOME` in `preBuild` rather than `preCheck`? | `pkgs/aiida-core/default.nix` (`preBuild`) |
| Why is cclib a flake input, and what does that cost on the NUR path? | `pkgs/harmonwig/default.nix` (the `cclib` argument), `flake.nix` (`cclibPkgs`) |
| Why can `aiida-gaussian` not be built at all, and what would it take? | `pkgs/aiida-gaussian/default.nix` (the `cclib` argument), `flake.nix` (`cclibPkgs`) |
| Why does `dbstep` skip `dbstep.graph` in its import check? Why is `pptk` not a dependency? | `pkgs/dbstep/default.nix` (`pythonImportsCheck`) |
| Why is `pythonRelaxDeps = true` on aqme rather than a list? Why is `test_csearch.py` disabled? | `pkgs/aqme/default.nix` |
| Why does `ccreg` drop its own `lwreg` requirement and add three undeclared ones? | `pkgs/ccreg/default.nix` (`pythonRemoveDeps`) |
| Why do three packages rewrite a `default-version` in `postPatch`? | `pkgs/mda-xdrlib/default.nix` (`postPatch`) |
| Why does MDAnalysis run no tests, and why is that not `doCheck = false`? | `pkgs/mdanalysis/default.nix` (the note above `pythonImportsCheck`) |
| Why does the AiiDA eval suite need a second, broken-allowing package set? | `tests/aiida/default.nix` (`brokenPkgs`) |

## Architecture

### Two entry points, one source of truth

`default.nix` is the NUR entry point and the canonical package list. `flake.nix` and
`overlay.nix` both derive from it:

- `flake.nix` → `legacyPackages` = `import ./default.nix`; `packages` = the derivations
  filtered out of that.
- `overlay.nix` → the same attrset minus the *reserved* keys.

`flake.nix` is a **flake-parts** flake: `systems` comes from `nix-systems/default`, per-system
outputs live in `perSystem`, and `nixosModules` / `overlays` sit in the system-agnostic `flake`
block. `perSystem`'s `pkgs` argument is the *un-overlaid* nixpkgs — `default.nix` applies the
overlays itself, so `legacyPackages` must use it as-is. The separate `pkgs'` in the `let` is the
overlaid set, and is what the eval and VM tests need.

**Reserved keys** (`lib`, `overlays`, `nixosModules`, `homeModules`, `darwinModules`,
`flakeModules`) are attrs in `default.nix` that must not be lifted into a nixpkgs overlay. The
`isReserved` predicate is duplicated in both `overlay.nix` and `ci.nix` — adding a new reserved
key means editing both.

### Adding a Python package takes three edits

The `qcfractal`, `aiida` and `cheminformatics` overlays in `overlays/default.nix` each inject
their Python packages into `pythonPackagesExtensions`, so they land in *every* `pythonX.pkgs`
set, **and** re-export the public ones as top-level `pkgs.*` aliases. `default.nix` then
re-exports the same names from `pkgs'.python313Packages`. All three routes are the *same*
derivation, which the `overlay-python-pin` and `aiida-overlay-python-pin` eval tests assert. So a
new package needs:

1. the `pself.callPackage` line in `overlays/default.nix`,
2. the top-level `inherit (final.python313Packages)` list in the same file,
3. the `inherit (py)` list in `default.nix`.

Steps 2 and 3 are for *public* packages only. The AiiDA and cheminformatics overlays between them
carry twenty-odd dependencies — `kiwipy`, `plumpy`, `disk-objectstore`, `pgsu`, `aiida-pseudo`,
`mdanalysis`, `colour-science`, `lwreg` and the rest — that stop at step 1 deliberately: they stay
reachable through `python313Packages` and are not top-level attributes, so `ci.nix` does not build
each of them in its own right. `tests/aiida/default.nix` spells out the public AiiDA list in
`exportedPackages`, a fourth hand-written copy that exists so the other three cannot drift apart
silently.

**A cclib dependant is the exception to all of this.** It is a top-level
`final.python3.pkgs.callPackage` in `overlays/default.nix` — one edit, not three — plus a line
in `default.nix`'s `inherit (pkgs')` list and one in `flake.nix`'s `packages` override. It is not a
`pythonPackagesExtensions` member because `python313Packages` is precisely the set that never has
cclib. `aiida-gaussian` breaks that rule and pays for it by being unbuildable; see the cclib split
above.

Inside a package derivation, dependencies on sibling packages resolve automatically through the
extended package-set fixpoint (`pself`) — do not thread them in manually. Non-Python packages
are plain `pkgs'.callPackage` calls in `default.nix`.

The top-level aliases are load-bearing, not a convenience: all three NixOS modules use
`lib.mkPackageOption pkgs "qcfractal"` / `"qcfractalcompute"` / `"aiida-core"`, which resolves
against the top level of `pkgs`. Dropping them makes every consumer of the overlay fail with
"qcfractal cannot be found in pkgs".

Packages driven by the modules also need `meta.mainProgram`: the modules launch them with
`lib.getExe`, which silently falls back to the *package* name, and none of the console scripts
is named after its package (`qcfractal` → `qcfractal-server`, `qcfractalcompute` →
`qcfractal-compute-manager`, `aiida-core` → `verdi`).

### What CI builds

`ci.nix` flattens `default.nix` and filters by `meta.broken`, `meta.license.free` and
`preferLocalBuild`. **A package that cannot build must carry `meta.broken = true;`** or CI and
cache population fail. `meta.broken` does not propagate to dependents and throws at *evaluation*
time, so each package that pulls in qcportal carries its own marking.

## Commands

**The `Justfile` is the source of truth for what CI runs.** `.github/workflows/build.yml` calls
the `ci-*` recipes rather than spelling the commands out, so `just ci <channel>` reproduces one
matrix leg end-to-end locally. Add CI logic there, not to the workflow.

```sh
just                      # list every recipe
just ci nixos-26.05       # one channel's full sequence; `just ci-matrix` for all three
just build qcfractal      # single package, NUR style; or nix build .#qcfractal
just check                # everything: both eval suites, every VM test, pre-commit hooks
just tests                # every non-VM suite reachable without the flake (see tests/AGENTS.md)
just harmonwig-tests      # the one suite that needs the flake, because cclib is an input
just vm-test server-local-db          # one VM test; needs KVM
just vm-test aiida-daemon-local-db    # the AiiDA VM tests are prefixed "aiida-"
just fmt / just lint / just hooks     # nixfmt, statix+deadnix, prek
```

Tooling comes from the devShell (`nix develop`, or direnv). Entering it also generates
`.pre-commit-config.yaml` from the `pre-commit.settings.hooks` block in `flake.nix` — that block
is the source of truth and the generated file is gitignored.

Note that `nixConfig.extra-substituters` is ignored unless the invoking user is in
`trusted-users`. Without that, `nix flake check` silently builds Psi4 from source no matter how
correct the pinning is — check for `warning: ignoring untrusted flake configuration setting`
before blaming the derivation hashes.

## Template leftovers

`.github/workflows/build.yml` still contains the `<YOUR_REPO_NAME>` / `<YOUR_CACHIX_NAME>`
placeholders, which keep the cachix and NUR-update steps disabled by their `if:` guards.
