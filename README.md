# nur-packages

**berquist's personal [NUR](https://github.com/nix-community/NUR) repository**

![Build and populate cache](https://github.com/berquist/nur/workflows/Build%20and%20populate%20cache/badge.svg)

## What's in it

### QCArchive / [QCFractal](https://github.com/MolSSI/QCFractal)

Python packages and two NixOS service modules for running a QCFractal server and a compute worker:

| Name                                                            | Description                                                 |
|-----------------------------------------------------------------|-------------------------------------------------------------|
| `qcportal`, `qcfractal`, `qcfractalcompute`, `qcarchivetesting` | QCArchive ecosystem packages                                |
| `nixosModules.qcfractal-server`                                 | `services.qcfractal.*` — the QCFractal database and web API |
| `nixosModules.qcfractal-compute`                                | `services.qcfractalCompute.*` — a QCFractal compute worker  |
| [`parsl`](https://github.com/Parsl/parsl)                       | the task executor used by QCFractal workers                 |

#### Support

Some quantum chemistry programs come from [NixOS-QChem](https://github.com/Nix-QChem/NixOS-QChem), re-exported here as `overlays.qchem` so that `pkgs.qchem.*` and the modules can be brought in together.

### [AiiDA](https://github.com/aiidateam/aiida-core)

`aiida-core`, its quantum chemistry plugins, and a NixOS service module for the daemon:

| Name                                                                          | Description                                                        |
|-------------------------------------------------------------------------------|--------------------------------------------------------------------|
| `aiida-core`                                                                  | the workflow manager itself (`verdi`)                              |
| `aiida-cp2k`, `aiida-orca`, `aiida-octopus`, `aiida-psi4`, `aiida-quantumespresso` | calculation, parser and workflow plugins                      |
| `nixosModules.aiida`                                                          | `services.aiida.*` — a PostgreSQL-backed profile and its daemon    |

A dozen dependencies that nixpkgs does not carry — `kiwipy`, `plumpy`, `disk-objectstore`,
`archive-path`, `pgsu`, `pgtest`, `aiida-pseudo`, `qe-tools` and the rest — come with them,
reachable as `python313Packages.*` rather than as top-level attributes.

The module defaults to the **ZeroMQ** broker (`core.zeromq`), which the daemon runs itself, so a
working instance needs nothing but PostgreSQL. RabbitMQ is available behind
`services.aiida.broker.backend = "core.rabbitmq"`, which also enables `services.rabbitmq` unless
you point it elsewhere. Plugins go in `services.aiida.plugins` so their entry points land in the
daemon's Python environment; the programs they drive go in `services.aiida.extraPackages`, which
is a different thing and reaches the daemon's `PATH` instead.

### [dotdrop](https://github.com/deadc0de6/dotdrop)

> Save your dotfiles once, deploy them everywhere

### [harmonwig](https://github.com/ispg-group/harmonwig)

Harmonic Wigner sampling of vibrational wavefunctions from quantum chemistry output. Its
[cclib](https://github.com/cclib/cclib) dependency is in neither nixpkgs nor NixOS-QChem, so it
comes from cclib's own flake — which means `nix build .#harmonwig` works but
`nix-build -A harmonwig` does not, and the NUR attribute carries `meta.broken` to say so.

## Using it

As a flake:

```nix
{
  inputs.nur-berquist = {
    url = "github:berquist/nur";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

then apply `nur-berquist.overlays.default` (everything) or one of `overlays.qcfractal`,
`overlays.aiida`, `overlays.dotdrop`, `overlays.harmonwig`, `overlays.qchem`, and import the
NixOS modules you actually enable — each is independent, and you do not need all of them.
`system-flake-snippet.nix` is a complete, copyable example of that wiring.

`overlays.harmonwig` is the one exception to "independent": it only yields a working harmonwig
when composed *after* cclib's own overlay, since that is where its cclib comes from.

A compute worker needs one manual step after `nixos-rebuild`: its QCFractal account lives in
PostgreSQL and its password must stay out of the store, so neither can be declared. Until you
have done it, `qcfractalcompute.service` crash-loops on a failed login. The exact procedure —
for one host or two, plus rotation and what to check when it fails — is in
[`docs/bootstrapping-worker-credentials.md`](docs/bootstrapping-worker-credentials.md).

Individual packages are available the usual NUR ways:

```sh
nix build .#qcfractal          # flake
nix-build -A qcfractal         # NUR entry point (default.nix)
nix build .#aiida-core
nix build .#dotdrop
nix build .#harmonwig          # flake only; see above
```

The QCArchive **and** AiiDA packages are pinned to **Python 3.13**: qcportal 0.65 is pydantic-v1
throughout and cannot be imported on 3.14, and `aiida-psi4` imports the same qcelemental v1
models. `pkgs.qcfractal` and `python313Packages.qcfractal` are the same derivation, as are
`pkgs.aiida-core` and `python313Packages.aiida-core`. See `pkgs/qcportal/default.nix` for the
mechanism and the condition for dropping the pin.

Psi4 is expensive to build from source. `flake.nix` reproduces NixOS-QChem's own instantiation
exactly so that `nix-qchem.cachix.org` is hit — which only works if your user is in
`trusted-users`, otherwise Nix ignores the flake's substituter.

## Hacking

`just` lists every recipe; `AGENTS.md` covers the architecture and the conventions.

```sh
nix develop            # or direnv; brings in just, nixfmt, statix, deadnix, prek
just check             # eval tests, VM tests, hooks — i.e. nix flake check
just tests             # every non-VM test suite
just ci                # one CI matrix leg, exactly as the workflow runs it
```
