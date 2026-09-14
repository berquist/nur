# Automating version updates

What is wired up, and why it is shaped this way.  This was a design document
until the updater was built; the reasoning is kept because it is still the
argument for the shape, and the measurements are kept because they are what the
shape follows from.  Several of them were wrong, and those are marked.

**In one paragraph.**  `nix-update`, driven by `scripts/update-packages.sh`
behind `just` recipes, with per-package policy inferred from the derivation by
`scripts/update-universe.nix` and *declared* only where the pin is deliberate.
Every proposed bump is gated on a real build.  The result is delivered as one
pull request per package, created through the forge's own API by
`scripts/forge-pr.sh` so that the forge signs the commit — GitHub today, Forgejo
after the move, one `FORGE=` switch apart.  The logic lives in `scripts/` and the
`Justfile`, so the same thing runs locally and on a runner.

## 1. Why not nixpkgs-update

[`nix-community/nixpkgs-update`](https://github.com/nix-community/nixpkgs-update)
is the right tool for exactly one repository, and this is not it.  It is a
long-running Haskell service, and what it automates is the *nixpkgs contribution
workflow* rather than the act of bumping a version:

- it operates on a nixpkgs checkout and its branch conventions (`staging`,
  `staging-next`, `master`), and decides where a bump belongs by rebuild count;
- it runs `nixpkgs-review` to build reverse dependencies, and reads **Hydra** to
  decide whether a package was already broken before the bump;
- it pings `meta.maintainers` by GitHub handle, and writes a PR body in a house
  style that reviewers of that repository expect;
- it opens pull requests through the **GitHub** API.  There is no Forgejo
  backend, and adding one is not a configuration change;
- its version sources (repology in particular) are keyed on nixpkgs attribute
  names, which say nothing about a NUR repository's.

The part of it worth having — "find the new version, rewrite the file, check it
builds" — is `nix-update`, a separate tool from the same organisation and the one
nixpkgs-update calls for that step.

`nvfetcher` is the other tool worth naming and rejecting: it maintains a
generated `sources.json` from a TOML manifest, which is a fine design for a
repository whose derivations are thin wrappers around fetches.  These are not —
the value here is in the patches, the deselections and the check phases, and
moving 146 sources into a manifest would separate each source from the comment
explaining why it is pinned where it is.

## 2. What the bot actually faces

Measured over `pkgs/` on 2026-09-13 — 146 packages.  **Count fetches by call
site, not by argument name**; the earlier version of this table did the latter
and was wrong about the one number that mattered.

| | Count |
|---|---|
| `fetchFromGitHub` as the primary source | 130 |
| `fetchFromGitLab` | 6 |
| `fetchPypi` | 6 |
| `fetchurl` | 3 |
| no fetch of its own | 1 (`dpdata-plugin-test`) |
| `version` of the form `X.Y.Z-unstable-YYYY-MM-DD` | **60** |
| a second fetch in the same derivation | 6 |

`just update-policy` prints the live version of the bottom half of that table;
do not re-derive it by hand.

One number decides the design.  **Two-fifths of the packages here follow a
branch rather than a tag**, because upstreams in this ecosystem tag rarely and
late — `vise` is 827 commits past its 2020 tag, `pydefect` 764 past v0.2.6 — so
"is there a newer release" is the wrong question for a large minority of this
repository and "what is `main` today" is the right one.

### The seven that were called permanently manual, and are not

The earlier version of this document wrote off five packages as manual forever.
That was two mistakes at once: the count was taken by grepping for fetcher
*names*, which matches the function-argument list at the top of every file, and
two of the cases were never actually read.  Having read all seven, **none of them
needs to be manual**, and `manual` is now a supported mode with no members:

| Package | The second fetch | What happens |
|---|---|---|
| `enumlib` | `symlib` v2.0.2 | a separate repository on its own cadence; a bump here does not touch it |
| `vesin` | `gpu-lite` at a fixed rev | the same |
| `yellowbrick` | dataset archives under a frozen `…/v1.0/` prefix | not keyed on the release at all |
| `fairchem-data-oc` | `bulks.pkl` at a stable URL | the same |
| `trexio` | `testSrc`, whose rev is `v${version}` | the rev moves with the bump; only the hash goes stale |
| `chemfiles` | `testsData`, pinned by upstream's `tests/CMakeLists.txt` | read `TESTS_DATA_GIT` out of the new source, rewrite the binding, recover the hash |
| `dpdata-plugin-test` | none — `version` is `0.0.0` and `src` is `dpdata`'s | nothing to bump, ever; `mode = "follows"` |

The two `derived` cases are what `scripts/refresh-hashes.sh` exists for: nix
prints the correct hash in the mismatch, and reading it back is a general
mechanism rather than a fix for two packages.

## 3. nix-update, and its three limits here

`nix-update` is in the locked nixpkgs at 1.16.0, and is in the devShell.  It
resolves an attribute, finds the latest version from the forge or index behind
its `src`, rewrites `version` and `hash` in the file `meta.position` names, and
can build the result.

Three things it will not do, each of which the driver covers:

1. **It does not know which bumps are unwanted.**  See §4.
2. **It rewrites one source.**  See §2 above and `scripts/refresh-hashes.sh`.
3. **It says nothing about whether the package still works.**  See §6.

The driver points it at `default.nix` rather than at the flake.  `--flake` runs
`nix flake metadata` — which "always re-copies the flake", twice per invocation —
and then evaluates flake.nix through flake-parts before it can reach one
attribute; `--file` is a lazy `import`, and measured 0.17s against roughly 4.8s
of CPU per package.  It also resolves four attributes the flake path could not
see at all, `nix-update`'s `eval.nix` looking in `flake.packages.${system}` and
the flake root but never in `legacyPackages`.  The cost is that `<nixpkgs>` is
no longer pinned by `flake.lock`, so the driver exports NIX_PATH from
`scripts/locked-nixpkgs.sh` before anything runs.

`scripts/update-packages.sh` greps `nix-update --help` for the flags it intends
to use before doing any work, so a renamed flag is one line at the start rather
than a silent no-op three hundred packages deep.

## 4. Policy: infer the rule, declare the exception

There is deliberately no central list of 146 packages.  It would be a fifth
hand-maintained copy of the package list, and it would put the reasoning
somewhere other than the code it governs, which is the one documentation rule
this repository is strict about.

`scripts/update-universe.nix` infers instead, from what the derivation already
says:

| What the derivation looks like | Inferred mode |
|---|---|
| `meta.broken` | `report` — never built, because `--build` would fail for an unrelated reason |
| `version` contains `-unstable-` | `branch` |
| otherwise | `stable` |

and then lets a package override that with `passthru.updatePolicy`, written next
to the `src` comment that already explains the pin:

```nix
passthru.updatePolicy = {
  mode = "pinned";
  reason = "fairchem-core pins this exact version with ==; see the note above src";
};
```

The modes are `stable`, `branch`, `pinned`, `manual`, `follows`, `report` and
`external`.  `external` is not declarable: `update-universe.nix` assigns it to
any attribute whose `meta.position` is not under `pkgs/`, which is how a guarded
backport that has fallen through to nixpkgs' own derivation — `monty` and
`pycifrw` on a new enough channel — is kept from having nixpkgs' file rewritten
underneath it.

**Three packages are `pinned` today**: `clusterscope` (the exact version
`fairchem-core` names with `==`), `node-graph` (v0.6.5, whose pre-`GraphTaskHandle`
API is the one `aiida-workgraph` and `aiida-pythonjob` are written against), and
`lobsterpy` (v0.6.1, the transitional release carrying both `cohp` and `coxx`).
`py-lmdb` is pinned in `overlays/default.nix` rather than `pkgs/`, so it is out
of reach of this mechanism entirely.

**`sisl` is not one of them**, though an earlier draft of this document said it
was.  Its note asks for *the release tag rather than the tip of main*, which is
exactly what `stable` mode already does; a newer sisl release is a bump worth
taking.  Pinning it would have frozen it for no reason.

### Following the branch it is already on

`--version=branch` follows the repository's **default** branch.  No package here
names a non-default one, so that is right for all 60 today, and
`passthru.updatePolicy.branch = "<name>"` is there for the first one that is not.

What actually enforces "the branch it is already on" is a date check: a bump
whose new `-unstable-YYYY-MM-DD` is *older* than the current one means the rev
has landed on a different line of development — an upstream retargeting its
default branch is the usual cause — and it is reported rather than committed.  A
declaration alone would not catch that, because the declaration would still be
naming a branch that had moved.

### The version guard, and why the date check was not enough

The date check answers for the rev.  A second guard answers for the version
string, and it turned out to be the busier of the two: twelve packages in the
first scan it ran against were offering a version *lower* than the one already
in the file.

The cause is structural rather than incidental.  A dozen packages here carry a
hand-written version because upstream's newest tag is years behind its default
branch — `vise` is 827 commits past v0.1.13 and `pydefect` 764 past v0.2.6, with
the real version in `__init__.py` — and `nix-update` reads the tag.  So a bump
that correctly moves the rev forward also writes the version backward, and the
file ends up claiming a release this repository passed long ago.  Two rules:

- the new version does not begin with a digit, which is a ref name that reached
  the version field (`mdanalysis` was offered `release-2.10.0`);
- the new version sorts before the current one under `sort --version-sort`.

Both compare a normalised prefix: the `-unstable-<date>` marker removed, and
then a trailing PEP 440 dev or pre-release segment, so that `0.12.dev20260807 ->
0.12` reads as the release it is rather than as a downgrade.  `sort` has never
heard of PEP 440, and four packages here publish dated dev versions.

A `rejected` row is a question for a human, not a defect.  The way out for a
package that genuinely needs the bump is `versionRegex` below, or a note saying
why the version is set by hand.

### When a tag does not spell the version

`passthru.updatePolicy.versionRegex` is `nix-update`'s `--version-regex`: one
capture group naming the version inside a tag.  The four `fairchem-*`
distributions are what forced it.  They share one monorepo which tags each
separately, so all four are offered the same release feed —
`fairchem_core-2.22.0`, `fairchem_data_omol-0.1.2` and the rest — and
`nix-update` can parse none of them as a version.  Each declares its own series:

```nix
passthru.updatePolicy.versionRegex = "fairchem_data_omat-(.*)";
```

It applies in `branch` mode too, which is the less obvious half: a snapshot's
version is `<newest reachable tag>-unstable-<date>`, drawn from that same feed,
so `fairchem-data-oc` was being handed `fairchem_core-2.22.0-unstable-…` — the
sibling distribution's tag.

**Declaring it also switches that package to the paginated releases API**, and
the two belong together.  `nix-update`'s default fetcher reads `releases.atom`,
which carries only the newest handful of releases; a repository that needs a
regex is by definition one with several series in that feed, so a series that
has not released lately can be missing from it altogether.  `fairchem-data-omat`
last tagged in November 2025 and its regex matched nothing at all — while
`fairchem-core` and `fairchem-data-omol` passed on the feed only because they
happened to be inside the window that week.  The API walk honours `GITHUB_TOKEN`
and costs one request per regexed package.

**It is not a universal escape hatch, and `firecrest-streamer` is the proof.**
That package is one directory inside the FirecREST v2 server monorepo, whose
tags version the *server*; there is no streamer series for a regex to match, so
it was offering `0.0.21 -> 2.6.0` and neither version guard objected — 2.6.0 is
well formed and sorts forward.  It is `mode = "report"`, and its rev moves by
hand.

`parsl` was the other permanent failure and needed a change to the derivation
rather than to the policy.  Its `src` was a `fetchurl` of a pythonhosted URL,
which addresses a file by a hash of its contents, so `nix-update` could neither
recognise it as PyPI — it matches `mirror://pypi` alone — nor construct the URL
of a release it had not already seen.  `fetchPypi` fetches the same bytes to the
same store path and is derivable from `version`.  A fetcher that hides the
version is worth spotting when the package is written.

### The universe, and how it stays honest

The attribute paths come from `default.nix`, not from a list: every top-level
derivation, plus the five packages that are deliberately not top level.
`update-universe.nix` then reads `pkgs/` with `builtins.readDir` and **fails if
any directory has no attribute path**.  That check is the point of keying off the
directory rather than the attribute set, and it earned its keep immediately:
`graphrc` turned out to be reachable from nothing at all, which `flake.nix` now
fixes.

It is also why `internalPackages` is down to two members.  Being a top-level
attribute is what makes `ci.nix` build a package in its own right, and there is
no good reason for a package this repository defines not to be one — so
everything is, except `chemfiles` and `trexio`, whose names are taken at the top
level by different derivations, and `tensorpotential`, `monty` and `pycifrw`,
which are out for reasons given at `default.nix`.

## 5. The driver

`scripts/update-packages.sh`, invoked from one-line `just` recipes:

```sh
just update-scan                  # what would move; nothing built, nothing written
just update-scan qcportal         # one package
just update-from-scan             # bump everything the last scan called would-update
just update-from-scan-pr          # the same, one pull request each
just update qcportal              # rewrite + build + fix hashes; leaves the tree dirty
just update-all                   # every actionable package
just update-pr qcportal           # the above, then branch + signed commit + PR
just update-batch 5               # what the scheduled workflow runs
just update-policy                # the resolved policy, as JSON; needs no daemon
just update-flake-inputs          # §8
```

### A scan is fast, and its answer outlives the terminal

A whole-repository scan is around 16 seconds.  It was 57 minutes, and the three
changes that account for that are worth knowing before anything is added to the
per-package path:

| | |
|---|---|
| `--file` rather than `--flake` | no store copy and no flake-parts evaluation per package; ~19× less CPU |
| `--no-src` in scan mode | `nix-update` rewrites a hash by building the fetcher with `outputHash = ""` and reading the right answer out of the *failure*, which leaves nothing in the store — so every moving package was downloading its source and discarding it, for a value the scan then restored |
| `--jobs`, defaulting to one per core capped at 8 | the work is forge round-trips, and a serial scan spent 79% of its wall clock waiting |

`--jobs` is refused outside scan mode: `--deliver` drives git and `--limit` is a
running count, and neither survives being raced.  Two attributes pointing at one
file would race their snapshots, so the driver checks for that and drops back to
a single worker rather than letting one bump vanish.

`update-scan` always writes `.scratch/update-scan.json`, and `update-from-scan`
reads its `would-update` rows back.  The scan's entire product is that list, and
it used to exist only in scrollback — so the work was thrown away unless someone
saved the log and retyped thirty-odd attribute names.  `rejected` and `failed`
rows are deliberately not carried over: the first is a guard's considered answer
and the second is a bug to fix.

Delivery is a flag (`--deliver=none|commit|pr`), not a mode of execution, and
`none` is the default everywhere including CI's scan job.  `--deliver=commit`
makes an ordinary local commit that *your* key signs, and refuses rather than
falling back to an unsigned one; the forge-signed path is for the unattended
runner and has no business overriding a human at a terminal.

**Scan mode restores the file rather than using a `git worktree`.**  `nix-update`
has no dry run, and the obvious workaround is wrong here twice over: a worktree
is checked out from a commit, so it would not see `passthru.updatePolicy`
annotations that are still uncommitted — which is exactly when someone runs a
scan — and flake evaluation ignores untracked files, so a newly added package
would be invisible.  Snapshotting the one file `nix-update` touches and putting
it back is simpler and sees the working tree as it is.

**One package per pull request.**  A batch branch would mean one failing package
blocks every other bump, which is the failure mode nixpkgs-update was designed
around and the reason it works package-at-a-time.

## 6. The verification gate

A bump that builds is the minimum, and for this repository the build *is* the
test: check phases here are large and load-bearing, so `nix-update --build`
running `pkgs/aiida-core`'s suite is a much stronger signal than a hash
comparison.  That also means the bot is expensive — some of these are
torch-sized closures — and must run somewhere that can afford it.

1. **Report-only first.**  A run that opens nothing and simply lists "N packages
   have a newer upstream" is worth having on its own; nobody knows that number
   today.  That is the scheduled job.
2. **Batch size.**  146 packages in one run is hours of build, past a hosted
   runner's six-hour ceiling.  `--limit` exists for that, and the workflow
   defaults the scheduled run to reporting only.
3. **A failed build is information, not an error.**  If `aiida-core` 3.0 fails
   its suite, the report says so and no pull request is opened.  That is the bot
   working.

## 7. Delivery, and why the forge signs

`scripts/forge-pr.sh` creates the commit through the forge's *contents* API
rather than with `git`.  Commits here are signed and an unattended runner cannot
hold the key, so the signature moves to the forge: GitHub signs web-flow
commits, and Forgejo signs API commits wherever `[repository.signing]
CRUD_ACTIONS` is configured.  The runner then needs a token and nothing else — no
key, no git identity, no push credentials.  `nix-update --commit` is therefore
unused.

Four calls, the same four on both forges:

| Step | GitHub | Forgejo |
|---|---|---|
| base sha | `GET /repos/{o}/{r}/git/ref/heads/{base}` | `GET /api/v1/repos/{o}/{r}/branches/{base}` |
| branch | `POST /repos/{o}/{r}/git/refs` | `POST /api/v1/repos/{o}/{r}/branches` |
| commit | `PUT /repos/{o}/{r}/contents/{path}` | `PUT /api/v1/repos/{o}/{r}/contents/{path}` |
| pull request | `POST /repos/{o}/{r}/pulls` | `POST /api/v1/repos/{o}/{r}/pulls` |

Auth is `Authorization: Bearer …` plus `Accept: application/vnd.github+json`
versus `Authorization: token …`.  `--dry-run` prints all four and issues none,
and needs no token.

**The branch is `update/<attr>` with no version in it**, so a re-run updates the
pull request that is already open rather than leaving a trail.  An existing
branch is deleted and recreated so the PR carries exactly one signed commit.
The earlier draft proposed `update/<attr>-<version>` and left "what happens to a
pull request nobody merges" as an open question; this is the answer to both.

**GitHub's contents API commits one file at a time**, which is the whole of this
script's reach.  That is enough — a `nix-update` rewrite touches one derivation
file and `nix flake update` touches one lock file — and anything wider is
reported rather than half-delivered.  Forgejo has a multi-file endpoint and
GitHub has the GraphQL `createCommitOnBranch` mutation if that ever has to
change.

### Two things to check on the first live run

Both fail silently, and both are recorded at the top of `scripts/forge-pr.sh`:

1. **A pull request opened with the automatic `GITHUB_TOKEN` does not trigger
   `pull_request` workflows.**  `build.yml` would never run on an updater PR,
   which defeats the review the PR exists for.  `.github/workflows/update.yml`
   uses `UPDATE_BOT_TOKEN` — a fine-grained PAT with contents and pull-request
   write — for exactly this reason.
2. **That the commit comes back `verified`.**  The script prints what the API
   says and warns when it is not; a commit the forge declined to sign means the
   whole arrangement is not doing what it claims.

### Forgejo

The workflow is written so it can be copied to `.forgejo/workflows/update.yml`
unchanged.  Forgejo reads that directory first and falls back to
`.github/workflows/`, so both forges can be live during the move.  Two things
made that possible: `uses:` is written as a full URL, because Forgejo resolves a
bare `actions/checkout` against its own action host rather than GitHub; and the
only other change needed is `FORGE=forgejo` plus `FORGE_HOST` in the `env`
blocks.

Runner-side, Forgejo Actions runs `act_runner`, configured on NixOS through
`services.gitea-actions-runner`.  Use a **self-hosted** runner with Nix already
installed and skip `install-nix-action` entirely; give it a label (`nix`) and
select it with `runs-on: nix`.  This repository's CI builds closures a hosted
runner cannot hold, which is true of `build.yml` too.

## 8. Flake inputs are a separate, much cheaper track

`scripts/update-flake-inputs.sh`: `nix flake update`, a gate, then the same
`forge-pr.sh`.  It covers `nixpkgs`, `cclib`, `nixos-qchem`, `flake-parts` and
the rest, needs none of the machinery above, and is complete on its own.

Two things to know:

- `nix flake check` is the real gate and it needs **KVM** for the VM tests.  A
  hosted GitHub runner has none, so `--gate=eval` is the default and forces the
  four evaluation checks only.  `--gate=full` is for a machine that has KVM.
- an input bump does **not** move what `just ci-matrix` tests.  The three matrix
  legs resolve `<nixpkgs>` from channel tarballs, not from `flake.lock` — see
  `scripts/locked-nixpkgs.sh`.  So the flake-input job and the package-version
  job cover genuinely different things, and neither substitutes for the other.

**Renovate** deserves a mention because it is the obvious "why not just use the
standard bot" answer: it has first-class Forgejo support and a Nix manager, and
nixpkgs has it at 44.37.1.  What its Nix manager does is `flake.lock`
maintenance — that is, precisely this section and nothing in §2 to §6.  It cannot
compute a `fetchFromGitHub` hash inside an arbitrary derivation.

## 9. Still to settle

- Whether `just ci-matrix` runs on the bot's pull requests.  Three full legs per
  package bump is not affordable; one leg, or eval only, probably is.
- Whether `-unstable-` packages should be bumped on every commit upstream makes,
  or only when the date is more than N days old.  60 packages moving weekly is a
  lot of noise for repositories that may see one commit a month.
- What a batch actually costs.  Until a dispatched run has been measured, the
  scheduled job reports and does not act.
- The remaining reading pass: 146 `src` comments, looking for a pin that is
  deliberate but not yet declared.  The first scan is what surfaces candidates —
  a package that moves a long way in one jump is the thing to look at.
