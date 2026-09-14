# Automating version updates

A design, not an implementation.  Nothing in this document is wired up yet.

**Recommendation in one paragraph.**  Do not run `nixpkgs-update`; it is a service built around
the nixpkgs repository and cannot be pointed at this one.  Use `nix-update`, which this repository
already invokes by hand, driven by a script in `scripts/` behind a `just` recipe, with per-package
policy expressed as `passthru` on the derivations that need it and *inferred* for the ones that do
not.  Gate every proposed bump on a real build.  Deliver the result as one Forgejo pull request
per package, opened by a bot account through the Forgejo API.  Keep the logic in the Justfile so
the same thing runs locally, on GitHub today and on Forgejo after the move.

## 1. Why not nixpkgs-update

[`nix-community/nixpkgs-update`](https://github.com/nix-community/nixpkgs-update) is the right
tool for exactly one repository, and this is not it.  It is a long-running Haskell service, and
what it automates is the *nixpkgs contribution workflow* rather than the act of bumping a version:

- it operates on a nixpkgs checkout and its branch conventions (`staging`, `staging-next`,
  `master`), and decides where a bump belongs by rebuild count;
- it runs `nixpkgs-review` to build reverse dependencies, and reads **Hydra** to decide whether a
  package was already broken before the bump;
- it pings `meta.maintainers` by GitHub handle, and writes a PR body in a house style that
  reviewers of that repository expect;
- it opens pull requests through the **GitHub** API.  There is no Forgejo backend, and adding one
  is not a configuration change;
- its version sources (repology in particular) are keyed on nixpkgs attribute names, which say
  nothing about a NUR repository's.

The part of it worth having — "find the new version, rewrite the file, check it builds" — is
`nix-update`, which is a separate tool from the same organisation and is what nixpkgs-update calls
for that step.  Taking `nix-update` and writing the 100 lines of driver around it is less work
than making nixpkgs-update believe this repository is nixpkgs, and the result is something that
can be read in one sitting.

## 2. What the bot would actually face

Measured over `pkgs/` on 2026-09-12 — 141 packages:

| | Count | Consequence |
|---|---|---|
| `fetchFromGitHub` | 126 | the well-trodden path |
| `fetchPypi` | 7 | `pytray`, `postopus`, `trexio`, and the four QCArchive packages |
| `fetchFromGitLab` | 6 | `ase-db-backends`, `pymatgen-io-aims`, `hiphive`, `trainstation`, `pyfhiaims`, `aiida-octopus` |
| `fetchurl` as the primary source | 1 | |
| `version` of the form `X.Y.Z-unstable-YYYY-MM-DD` | **69** | pinned to a commit, not a tag — needs branch mode, not tag mode |
| exactly one fetcher call | 136 | `nix-update` can rewrite these unaided |
| two fetcher calls | 4 | `chemfiles`, `enumlib`, `fairchem-data-oc`, `trexio` |
| no fetcher at all | 1 | `dpdata-plugin-test`, which builds from `dpdata`'s `src` one directory down |

Two numbers there decide the design.  **Half the packages here follow a branch rather than a
tag**, because upstreams in this ecosystem tag rarely and late — `vise` is 827 commits past its
2020 tag, `pydefect` 764 past v0.2.6 — so "is there a newer release" is the wrong question for
most of this repository and "what is `main` today" is the right one.  And **five packages have a
source `nix-update` cannot fully rewrite**: a second `fetchFromGitHub` for a submodule
(`enumlib`'s symlib, `chemfiles`' test data), a `fetchurl` for a data file
(`fairchem-data-oc`'s 36 MB bulk database), a restored test file (`trexio`), or no source of its
own at all (`dpdata-plugin-test`).  Those five are manual, permanently, and the design has to say
so rather than produce a half-updated derivation.

## 3. nix-update, and its three limits here

`nix-update` is in the locked nixpkgs at **1.16.0**.  It resolves an attribute, finds the latest
version from the forge or index behind its `src`, rewrites `version` and `hash` in the file that
`meta.position` names, and can build the result.  `AGENTS.md` already documents the invocation
this repository uses by hand:

    nix-update --flake python313Packages.mdanalysis

Three things it will not do, each of which the driver has to cover:

1. **It does not know which bumps are unwanted.**  Several packages here are pinned deliberately
   and a bot that "helpfully" moves them undoes deliberate work — see §4.
2. **It rewrites one source.**  For the five packages in the table above, a successful
   `nix-update` run leaves a derivation whose second hash is now wrong, and the failure surfaces
   as a build error some minutes later, or worse as a silently stale data file.
3. **It says nothing about whether the package still works.**  Hash and version are syntax; this
   repository's value is in its check phases.  See §6.

Confirm the exact flag spellings against `nix-update --help` before writing the script — the ones
this design assumes are `--flake`, `--version=branch`, `--build`, `--commit` and
`--write-commit-message`.  1.16.0 is what the pin has; do not write the script against memory.

## 4. Policy: infer the rule, declare the exception

Do **not** write a central list of 141 packages.  It would be a fifth hand-maintained copy of the
package list — `AGENTS.md` already tracks four — and it would put the reasoning somewhere other
than the code it governs, which is the one documentation rule this repository is strict about.

Infer instead, from what the derivation already says:

| What the derivation looks like | Inferred mode |
|---|---|
| `version` contains `-unstable-` | follow the branch (`--version=branch`) |
| otherwise | follow tags and releases |

That is correct for 140 of 141 packages without anyone writing anything down.  The exceptions
declare themselves, next to the `src` comment that already explains them:

```nix
passthru.updatePolicy = {
  mode = "pinned";
  reason = "fairchem-core asks for == 0.0.18; see the note above src.";
};
```

Three modes are enough:

- **`pinned`** — never bump; the reason is printed in the run's report, so a human reading it sees
  *why* a package was skipped rather than wondering whether the bot forgot.  Known members today:
  `clusterscope` (pinned to the exact version `fairchem-core`'s `==` names), `sisl` (a tag,
  because the commits past it break the build), `node-graph` (v0.6.5 exactly, one commit behind
  its own main), `lobsterpy` (v0.6.1, the transitional release carrying both `cohp` and `coxx`),
  and — in `overlays/default.nix` rather than `pkgs/`, so out of reach of this mechanism
  entirely — `py-lmdb`, which is pinned *down*.
- **`manual`** — the five multi-source packages of §2.  The bot reports "a newer version exists"
  and stops.  That is worth having: the report is the notification nobody gets today.
- **absent** — the inferred rule applies.

**The first pass is a reading task, not a coding one.**  Somebody has to open all 141 `src`
comments once and add `passthru.updatePolicy` wherever the pin is deliberate.  Until that is done
the bot must run in report-only mode, because the cost of getting it wrong is silently undoing a
decision that took a day to reach.  Budget a session for it; the comments are all there.

## 5. The driver

`scripts/update-packages.sh`, invoked from a one-line `just` recipe, per the standing rule about
recipes that outgrow a few lines.  Sketch — this passes `shellcheck` and `shfmt` as written, but
it is a shape, not a finished script:

```bash
#!/usr/bin/env bash
#
# Run nix-update over the packages this repository defines, honouring
# ./update-policy.nix, and leave one commit per successful update.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

policy="$(nix eval --json --file ./update-policy.nix)"

mapfile -t attrs < <(jq --raw-output 'keys[]' <<<"$policy")

failed=()
for attr in "${attrs[@]}"; do
    mode="$(jq --raw-output --arg a "$attr" '.[$a].mode' <<<"$policy")"
    case "$mode" in
        pinned)
            reason="$(jq --raw-output --arg a "$attr" '.[$a].reason' <<<"$policy")"
            printf 'skip    %s -- %s\n' "$attr" "$reason"
            continue
            ;;
        branch) spec=(--version=branch) ;;
        stable) spec=() ;;
        *)
            printf 'unknown mode %q for %s\n' "$mode" "$attr" >&2
            exit 1
            ;;
    esac

    if nix-update --flake --build --commit "${spec[@]}" "$attr"; then
        printf 'updated %s\n' "$attr"
    else
        printf 'FAILED  %s\n' "$attr"
        failed+=("$attr")
    fi
done

printf '%d package(s) failed to update\n' "${#failed[@]}"
[[ ${#failed[@]} -eq 0 ]]
```

(The sketch reads a generated `update-policy.nix` for clarity.  In the real thing that file is
itself produced by a `nix eval` over the package set, applying §4's inference and reading
`passthru.updatePolicy` — there is no hand-written policy file.)

**Where the attribute names come from** is the part that only became possible recently.  A bot
needs an attribute path for every package, and 70 of the packages here are internal — reachable
until now only through `python313Packages`, which is the whole 3.13 set and cannot be enumerated.
`default.nix`'s `internalPackages` is exactly the bounded list of them, so the bot's universe is

    (top-level derivations of default.nix) ++ (internalPackages)

and that is the same set `ci.nix` builds.  Enumerating it needs no new list.

**One package per commit, one commit per branch.**  `nix-update --commit` writes the commit
message; the driver branches as `update/<attr>-<new-version>` before running it.  A batch branch
would mean one failing package blocks every other bump, which is the failure mode nixpkgs-update
was designed around and the reason it works package-at-a-time.

## 6. The verification gate

A bump that builds is the minimum, and for this repository the build *is* the test: check phases
here are large and load-bearing, so `nix-update --build` running `pkgs/aiida-core`'s suite is a
much stronger signal than a hash comparison.  That also means the bot is expensive — some of these
are torch-sized closures — and must run on a machine that can afford it.

Three practical consequences:

1. **Report-only first.**  A first run that opens no pull requests and simply lists "42 packages
   have a newer upstream" is worth having on its own; nobody knows that number today.
2. **Batch size.**  Bumping 141 packages in one nightly run is hours of build.  Weekly, or a
   rolling subset (say, everything untouched for 30 days), is the realistic cadence.  Start
   weekly.
3. **A failed build is information, not an error.**  If `aiida-core` 3.0 fails its suite, the
   report says so and no pull request is opened.  That is the bot working.

## 7. Forgejo

The move is what makes this worth designing now rather than adopting a GitHub-shaped tool.

**Runner.**  Forgejo Actions runs `act_runner`, configured on NixOS through
`services.gitea-actions-runner` pointed at the Forgejo instance.  Use a **self-hosted** runner
with Nix already installed, and skip `install-nix-action` entirely: this repository's CI builds
closures that a hosted runner cannot hold, which is true of the existing build workflow too.
Give the runner a label (`nix`) and select it with `runs-on: nix`.

**Workflow location.**  Forgejo reads `.forgejo/workflows/` first and falls back to
`.github/workflows/`.  Putting the update workflow in `.forgejo/workflows/update.yml` and leaving
`build.yml` where it is keeps both forges working during the move.

**`uses:` resolution** is the one real incompatibility.  Forgejo resolves a bare
`uses: actions/checkout@v4` against its own configured action host (code.forgejo.org by default),
not GitHub.  Two ways out, and the second is better here:

1. write the full URL — `uses: https://github.com/actions/checkout@v4` — which Forgejo supports;
2. do not use third-party actions at all.  The whole job is `git`, `nix` and `curl`, and this
   repository's own principle is that the Justfile holds the logic.

Sketch:

```yaml
name: "Propose version updates"
on:
  schedule:
    - cron: "17 4 * * 1"
  workflow_dispatch:
jobs:
  update:
    runs-on: nix
    steps:
      - uses: https://github.com/actions/checkout@v4
      - name: Rewrite and build
        run: just update-packages
      - name: Open one pull request per update
        env:
          FORGEJO_TOKEN: ${{ secrets.UPDATE_BOT_TOKEN }}
        run: just update-prs
```

**Opening the pull request.**  Forgejo's API is Gitea-compatible:
`POST /api/v1/repos/{owner}/{repo}/pulls` with `head`, `base`, `title` and `body`, authenticated
by a token in the `Authorization: token …` header.  Either `curl` it, or use `tea`, the official
Gitea/Forgejo CLI, which nixpkgs has at 0.15.1.  Prefer `curl`: one dependency fewer, and the
request is three fields.

**Credentials.**  A dedicated bot account with write access, and a token stored as an Actions
secret.  Not the repository's automatic token: in Forgejo its permissions are scoped per workflow
and a human-owned personal token in a scheduled job is worse than a bot account in every way that
matters.

**Signing is the open question.**  Commits in this repository are GPG-signed, and a bot cannot
sign as its author.  Three options, in order of preference: give the bot account its own key and
mark it as a bot in Forgejo; let the bot's commits be unsigned and require that the *merge* be
signed by a human, which is the normal shape for this and what Forgejo's branch protection can
enforce; or have the bot only ever open an issue with the diff, never a branch.  Settle this
before the first run, not after.

## 8. Flake inputs are a separate, much cheaper track

`nix flake update` on a schedule, opening one pull request, covers `nixpkgs`, `cclib`,
`nixos-qchem`, `flake-parts` and the rest.  It needs none of the machinery above: no hashes to
compute, no policy, no per-package anything.  Do this one **first** — it is an afternoon, and it
exercises the whole Forgejo delivery path (runner, token, PR creation, signing decision) against a
change that is trivial to review.

Two things to know:

- `nix flake check` here is the gate, and it needs KVM for the VM tests.  The runner has to have
  it, or the job is limited to the eval checks.
- an input bump does **not** move what `just ci-matrix` tests.  The three matrix legs resolve
  `<nixpkgs>` from channel tarballs, not from `flake.lock` — see `scripts/locked-nixpkgs.sh`.  So
  the flake-input job and the package-version job cover genuinely different things, and neither
  substitutes for the other.

**Renovate** deserves a mention because it is the obvious "why not just use the standard bot"
answer: it has first-class Forgejo support and a Nix manager, and nixpkgs has it at 44.37.1.  What
its Nix manager does is `flake.lock` maintenance — that is, precisely §8 and nothing in §2 to §6.
It cannot compute a `fetchFromGitHub` hash inside an arbitrary derivation.  So Renovate is a
legitimate way to do the cheap half, and no help at all with the expensive half.  If a second tool
is unwelcome, `nix flake update` in a workflow does the same job in ten lines.

`nvfetcher` is the other tool worth naming and rejecting: it maintains a generated `sources.json`
from a TOML manifest, which is a fine design for a repository whose derivations are thin wrappers
around fetches.  These are not — the value here is in the patches, the deselections and the check
phases, and moving 141 sources into a manifest would separate each source from the comment
explaining why it is pinned where it is.

## 9. Order of work

1. **Flake inputs on a schedule.**  Proves the Forgejo runner, the bot account, the token and the
   signing decision against a trivial change.
2. **Report-only package scan.**  `scripts/update-packages.sh` with no `--commit`, printing what
   *would* move.  This answers a question nobody has an answer to today and costs no builds.
3. **The `passthru.updatePolicy` reading pass.**  One session with all 141 `src` comments.  Until
   this is done, step 4 is not safe.
4. **Turn on commits and pull requests**, weekly, package at a time, build-gated.
5. **Report the five manual packages** rather than touching them.

## 10. Still to settle

- Which branch the bot targets, and whether `just ci-matrix` runs on its pull requests.  Three
  full legs per package bump is not affordable; one leg, or eval only, probably is.
- What happens to a pull request nobody merges.  nixpkgs-update's answer is to close and reopen
  with the newest version; the cheap answer is to force-push the branch.
- Whether `-unstable-` packages should be bumped on every commit upstream makes, or only when the
  date is more than N days old.  69 packages moving weekly is a lot of noise for repositories that
  may see one commit a month.
- Whether the bot should also run `just fmt` and the pre-commit hooks before proposing — it should,
  since a rewritten `version` line can leave a file nixfmt would change.
