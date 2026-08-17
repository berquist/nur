# AGENTS.md

Guidance for working in this repository.

## What this is

berquist's personal [NUR](https://github.com/nix-community/NUR) repository, built from
`nur-packages-template`. It holds four unrelated bodies of work:

- the **QCArchive/QCFractal ecosystem** — Python packages (`qcportal`, `qcfractal`,
  `qcfractalcompute`, `qcarchivetesting`, `parsl`) plus two NixOS service modules.
- the **AiiDA ecosystem** — `aiida-core`, five quantum chemistry plugins (`aiida-cp2k`,
  `aiida-orca`, `aiida-octopus`, `aiida-psi4`, `aiida-quantumespresso`), the fifteen-odd
  dependencies of both that nixpkgs does not carry, and one NixOS service module. Together with
  QCArchive this is the bulk of the repo. It shares the `python313` pin with QCArchive and
  nothing else; the two overlays are separate so that a consumer can take one without the
  other's closure.
- **dotdrop** — a standalone dotfile-manager CLI, not in nixpkgs. It shares nothing with the
  above and is deliberately kept separate: its own overlay, its own test subdirectory, and the
  default `python3` rather than the 3.13 pin.
- **harmonwig** — likewise a standalone CLI, and the one package here that is only buildable
  through the flake, because its `cclib` comes from a flake input.

The `nixos-qchem` flake input supplies quantum-chemistry programs as `pkgs.qchem.*` and is
re-exported as `overlays.qchem`. The `cclib` flake input supplies cclib, which is nowhere in
nixpkgs and which upstream ships a flake for.

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
| Why is nixpkgs' `pymatgen` interpreter gate lifted, and why at that one call site? | `overlays/default.nix` (the `aiida-core` `callPackage`) |
| Why does `aiida-psi4` patch `setup.json`? What is `reentry` doing there? | `pkgs/aiida-psi4/default.nix` (`postPatch`) |
| Why does every AiiDA package set `HOME` in `preBuild` rather than `preCheck`? | `pkgs/aiida-core/default.nix` (`preBuild`) |
| Why is cclib a flake input, and what does that cost harmonwig on the NUR path? | `pkgs/harmonwig/default.nix` (the `cclib` argument), `flake.nix` (`harmonwigPkgs`) |

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

The `qcfractal` and `aiida` overlays in `overlays/default.nix` each inject their Python packages
into `pythonPackagesExtensions`, so they land in *every* `pythonX.pkgs` set, **and** re-export
the public ones as top-level `pkgs.*` aliases. `default.nix` then re-exports the same names from
`pkgs'.python313Packages`. All three routes are the *same* derivation, which the
`overlay-python-pin` and `aiida-overlay-python-pin` eval tests assert. So a new package needs:

1. the `pself.callPackage` line in `overlays/default.nix`,
2. the top-level `inherit (final.python313Packages)` list in the same file,
3. the `inherit (py)` list in `default.nix`.

Steps 2 and 3 are for *public* packages only. The AiiDA overlay carries a dozen dependencies —
`kiwipy`, `plumpy`, `disk-objectstore`, `pgsu`, `aiida-pseudo` and the rest — that stop at step
1 deliberately: they stay reachable through `python313Packages` and are not top-level
attributes, so `ci.nix` does not build each of them in its own right. `tests/aiida/default.nix`
spells out the public list in `exportedPackages`, a fourth hand-written copy that exists so the
other three cannot drift apart silently.

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
