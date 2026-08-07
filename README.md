# nur-packages

**berquist's personal [NUR](https://github.com/nix-community/NUR) repository**

![Build and populate cache](https://github.com/berquist/nur/workflows/Build%20and%20populate%20cache/badge.svg)

## What's in it

**QCArchive / QCFractal** — Python packages and two NixOS service modules for running a
QCFractal server and a compute worker:

| | |
|---|---|
| `qcportal`, `qcfractal`, `qcfractalcompute`, `qcarchivetesting` | QCArchive 0.65, none of which are in nixpkgs |
| `parsl` | the task executor `qcfractalcompute` runs on |
| `nixosModules.qcfractal-server` | `services.qcfractal.*` — web API, PostgreSQL wiring, Alembic migrations |
| `nixosModules.qcfractal-compute` | `services.qcfractalCompute.*` — a local worker that discovers QC programs on its `PATH` |

**dotdrop** — the dotfile manager, also not in nixpkgs. Unrelated to the above.

Quantum-chemistry programs (Psi4, CFOUR, NWChem, …) come from
[NixOS-QChem](https://github.com/Nix-QChem/NixOS-QChem), re-exported here as `overlays.qchem`
so that `pkgs.qchem.*` and the modules can be brought in together.

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
`overlays.dotdrop`, `overlays.qchem`, and import the NixOS modules you actually enable — each is
independent, and you do not need both. `system-flake-snippet.nix` is a complete, copyable
example of that wiring.

Individual packages are available the usual NUR ways:

```sh
nix build .#qcfractal          # flake
nix-build -A qcfractal         # NUR entry point (default.nix)
nix build .#dotdrop
```

The QCArchive packages are pinned to **Python 3.13**: qcportal 0.65 is pydantic-v1 throughout
and cannot be imported on 3.14. `pkgs.qcfractal` and `python313Packages.qcfractal` are the same
derivation. See `pkgs/qcportal/default.nix` for the mechanism and the condition for dropping
the pin.

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
