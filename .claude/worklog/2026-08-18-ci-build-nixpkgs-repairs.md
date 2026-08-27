---
date: 2026-08-18
slug: ci-build-nixpkgs-repairs
status: partial
sessions: ["25b16388-d637-41fc-aff4-d239f454ae60"]
touches:
  - "scripts/demux-build-log.sh"
  - "Justfile"
  - ".editorconfig"
  - "overlays/default.nix"
  - "pkgs/{qmzyme,pgsu,postopus}/**"
  - "tests/cheminformatics/default.nix"
  - ".scratch/nixpkgs-{rdkit,octopus}*.patch"
  - "AGENTS.md"
---

# Reading a --keep-going log, and the two nixpkgs bugs it was hiding

## Ask

> 1. Read "log_ci" to see what the current problems are.  2. Related to reading the log, consider
> writing a tool that reorganizes the output so that each task isn't interleaved; for example, all
> "python3.13-postopus" lines should appear together in the order that they appear.  3. Write a Just
> recipe that builds a package via the flake

> Patch the upstream rdkit and octopus packages. Tell me what commands to run outside of the sandbox

> sorry, I didn't mean to interrupt, keep going

> ok, go back to what you were doing. you can read "log_ci" again by running it through "just
> demux-log".

> [terminal output, recorded under Out-of-band] then read "qmzyme.log" then demux the refreshed
> "log_ci".

> yes, apply both and fix the comment

> write the worklog

## Plan

No plan mode was used.  The three numbered items in the first prompt were the plan, and each later
prompt set the next step directly.

## Out-of-band

The user ran the octopus verification block from the previous turn.  It failed on a mistake in the
command *I* had written:

```
$ src=$(nix-build --no-out-link '<nixpkgs>' -A python313Packages.postopus.src)
error: attribute 'postopus' in selection path 'python313Packages.postopus.src' not found inside
path 'python313Packages', whose contents are: { APScheduler = «thunk»; … }
```

`postopus` is this repo's package, not nixpkgs'.  It needed `nix-build . -A …`, which applies the
overlays.  The rest of the block then cascaded — `tar` got an empty path, and octopus ran in an
empty directory and said `Cannot open input file!`.  The check was moot by then anyway; see
Outcome.

The user also ran `just ci-build` twice out of band and left `log_ci` and `qmzyme.log` in the tree
for reading.

## Changes

Two commits, both landed by the user.

**82ecd9e** — `fix: repair nixpkgs' rdkit and octopus, and make ci-build logs readable`

- `scripts/demux-build-log.sh` — buckets a `nix build -L` log by the `name> ` prefix and replays
  each bucket contiguously, nix's own lines first.  New.
- `Justfile` — `just demux-log`, and `just build-flake`, the only route that can build the five
  cclib dependants (`just build harmonwig` stops at "marked as broken").
- `.editorconfig` — `scripts/` was already 4-space with indented case arms, but with no config
  `shfmt` defaults to tabs and rewrites both scripts.
- `overlays/default.nix` — the two nixpkgs repairs, below.
- `tests/cheminformatics/default.nix` — asserts the rdkit repair reaches all three package sets a
  dependant might be built from.
- `.scratch/nixpkgs-rdkit-dist-info.patch`, `.scratch/nixpkgs-octopus-netcdf-fix.patch` — the same
  two fixes as upstreamable patches, matching the aiormq and aio-pika convention already there.
- `AGENTS.md` — two pointer rows.

**6bfac21** — `fix: the failures the rdkit and octopus repairs uncovered`

- `pkgs/pgsu/default.nix` — `env.postgresqlEnableTCP = 1;`.
- `pkgs/qmzyme/default.nix` — `openbabel` in `nativeCheckInputs`, and a corrected comment.

## Outcome

`just ci-build` planned twelve derivations.  Three failed on their own account; the other nine were
cascades from `pgsu`.

**rdkit — fixed, verified.** nixpkgs builds rdkit with CMake and `pyproject = false`, so
site-packages gets a bare `rdkit/` tree with no `.dist-info`.  It imports perfectly and is invisible
to `importlib.metadata`, which is what `pythonRuntimeDepsCheckHook` uses — so qmzyme failed with
`- rdkit not installed` while rdkit sat in its closure.  The repair synthesises `METADATA`.
Confirmed offline before committing, by running nixpkgs' real
`python-runtime-deps-check-hook.py` against a synthesized dist-info: the rdkit line disappears while
an unrelated missing package still reports, so the hook was resolving rather than passing
everything.  Confirmed for real in the next `ci-build` — qmzyme got past the check and ran its suite
for the first time.

**octopus — fixed, verified.** All 68 postopus tests downstream of a calculation errored with
`Failed to run 'octopus'` and nothing to say why.  The existing comment in the overlay blamed
OpenMPI, and `enableMpi = false` was already in place — but reading the failing `.drv` showed it
*had* taken effect and the serial octopus was in use, so that diagnosis no longer held.

The reason nothing appeared in the build log is that postopus' test inputs set
`stdout = "gs_stdout.txt"` and `stderr = "gs_stderr.txt"`, so octopus writes its own diagnostics to
files pytest never reads.  Extracting the sdist and running the serial binary by hand on
`tests/data/methane/inp_gs` gave the answer immediately:

```
* Octopus was compiled without NetCDF support.
* It is not possible to write output in NetCDF format.
```

Every generating input asks for `OutputFormat = netcdf + vtk + plane_z + xcrysden`.  nixpkgs puts
the **C** `netcdf` in octopus' `buildInputs`, but `CMakeLists.txt` asks for
`find_package(netCDF-Fortran MODULE)`, which resolves `netcdf-fortran` through pkg-config — a
separate derivation, `pkgs.netcdffortran`.  It is never found, `HAVE_NETCDF` is never set, and there
is no `OCTOPUS_NetCDF` flag to force it.  The MPI build has the same gap.

Proven by the next `ci-build`: the plan dropped to eleven derivations with `postopus` absent, so it
had built.  It cannot have been substituted, since it depends on our overridden octopus.  That is
better evidence than the hand-run check would have been, which is why the broken verification
command above did not matter.

**pgsu and qmzyme — fixed, not built.** Both are the next layer, and neither has been through a
build.

`pgsu::test_grant_priv` is what the locale fix in 78f3b9f uncovered.  It creates a role, then
reconnects *as that role* using `pgsu.dsn.get('host') or 'localhost'`; pgsu connected over the Unix
socket, so its dsn has no host, the fallback wins, and the reconnect goes over TCP to a cluster
`postgresqlTestHook` started with `listen_addresses = ''`.

qmzyme's suite, running for the first time, failed six tests on `FileNotFoundError: 'obabel'` from
`QMzyme/aqme/qprep.py` — a vendored copy of AQME — reached from `write_input()`.

### Rejected

**`pythonRemoveDeps = [ "rdkit" ]` on each dependant.** The cheap fix, and it keeps the cached
rdkit: overriding rdkit rebuilds a large C++ package from source rather than substituting it.
Rejected because the user asked for the upstream fix and because `aqme` and `digichem-core` declare
rdkit too, so every dependant would otherwise carry the same workaround.  The cost is recorded in
the comment at the override, with this alternative named, so the trade can be reversed cheaply.

**Making the rdkit repair a `let` binding**, the way `pymatgen` is handled in the aiida overlay to
keep an override invisible to consumers.  Rejected because the cclib dependants reach rdkit through
`final.python3.pkgs` while qmzyme uses `python313Packages`; only a `pythonPackagesExtensions` member
covers both.  The new eval test exists because that difference is silent — an unrepaired rdkit
builds and imports fine, and nothing complains until some dependant's build fails, pointing at the
wrong package.

**Trusting the existing MPI diagnosis for postopus.** The comment in the overlay described exactly
the observed symptom, which made it tempting to stop there.  Reading the `.drv` to see which octopus
was actually used is what showed the fix was already in place and the cause was something else.

### Two bugs written and fixed in the demuxer, both silent

Recorded because both are easy to write again.  The bucket registration was first written as a
helper returning the path through `$(…)` — a command substitution is a subshell, so every update to
the bookkeeping arrays was discarded, and the script printed nothing at all.  Then, when the prefix
pattern moved into a variable to be shared, `\>` stopped meaning an escaped `>` and became GNU
regex's end-of-word anchor, which matches after `error`, `warning` and `building` — turning every
nix diagnostic into a section of its own.  Both were caught by checking that the per-section line
counts sum to `wc -l`, which is worth doing on any log this thing is pointed at.

## Follow-ups

- **`just lint` fails repo-wide**, and did before this session.  `deadnix --fail .` descends into
  `wc/cclib/`, a clone, and reports unused bindings in someone else's flake.  `wc/` is in
  `.gitignore` and `statix` honours it; `deadnix` does not.  Wants `--exclude wc`.
- **`log_ci`, `log_check`, `log_ci_matrix` are untracked and not ignored.** They are build logs and
  keep showing up in `git status`.  Either ignore them or write them somewhere already ignored.
- **`nix-build '<nixpkgs>' -A <one of ours>` is a trap**, and I fell into it when writing the
  verification commands.  Anything this repo adds needs `nix-build . -A …` or `just build`.  Worth a
  line in AGENTS.md next to the `just build` / `just build-flake` split.
- **Upstream the two `.scratch/` patches.** Both apply cleanly to nixpkgs and both patched files are
  nixfmt-clean; neither has been sent.
- **Nothing to capture from the repeated commands.** The most-repeated command by far was sourcing a
  reconstructed `PATH`, which was scaffolding for a broken sandbox rather than a workflow step; the
  formatters and linters are already `just fmt-check`, `just lint` and `just hooks`; and the one
  genuine new step, `scripts/demux-build-log.sh`, became `just demux-log` in this session.
- **The sandbox came up with an empty `PATH`** — no `ls`, no `nix`, only `/bin/bash`. Everything was
  still in `/nix/store`, so a `PATH` was rebuilt from store paths by hand.  Worth knowing if a later
  session looks inexplicably broken; it is an environment fault, not a repo one.
