# Worklog

One file per session that amounted to a plan or a multi-step task, newest first. Each holds the
prompts verbatim, the plan inlined, what changed, and — most usefully — what was tried and
abandoned.

Grep the `touches:` globs in the front matter before changing a file, to find the history behind
it.

- [2026-08-17 cheminformatics family](2026-08-17-cheminformatics-family.md) — 16 new packages and two overlays; found that `python3Packages` is not `python3.pkgs`, so harmonwig's cclib had never resolved. `git archive | nix hash path` gives fetchFromGitHub hashes offline.
- [2026-08-17 AiiDA ecosystem](2026-08-17-aiida-ecosystem.md) — 20 new packages, `services.aiida`, and two test suites; every hash but five recovered offline from `uv.lock`, nothing built yet.
