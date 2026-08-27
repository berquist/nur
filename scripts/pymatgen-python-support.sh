#!/usr/bin/env bash
#
# pymatgen-python-support.sh — can nomadPython move to a newer interpreter yet?
#
# WHY THIS EXISTS
#
# overlays/nomad.nix builds NOMAD against python312 rather than python313 for
# exactly one reason: nixpkgs marks pymatgen
#
#     disabled = pythonAtLeast "3.13";
#
# and nomad-lab requires pymatgen>=2025.10.7 unconditionally — the materials
# normalizer is not optional, so the marker is load-bearing for the whole
# NOMAD closure.  Nothing else in that closure needs 3.12.
#
# The marker looks conservative rather than real: every one of pymatgen's own
# dependencies (numba, vtk, moyopy, spglib, matplotlib, …) builds fine on 3.13,
# and upstream pymatgen declares requires-python = ">=3.11" with 3.13 in its
# own CI.  But "looks conservative" is not evidence, and clearing another
# repo's `disabled` flag on a hunch is how you end up debugging a Cython
# extension at 1 a.m.  This script produces the evidence instead.
#
# WHAT IT DOES
#
# For each interpreter named on the command line (default: python313
# python314), it:
#
#   1. reports whether nixpkgs still marks pymatgen disabled there — if the
#      marker is gone, there is nothing left to work around and the overlay
#      can simply move;
#   2. builds pymatgen with the marker cleared, running upstream's full test
#      suite (nixpkgs enables pytestCheckHook for it, so a green build *is* a
#      green suite);
#   3. if that passes, instantiates the whole nomad-lab closure against the
#      same interpreter, because pymatgen is necessary but not sufficient.
#
# Clearing the marker is done as `.override { pythonAtLeast = _: false; }`
# rather than `.overridePythonAttrs (_: { disabled = false; })`.  `disabled` is
# enforced through lib.extendDerivation on the *finished* derivation
# (mk-python-derivation.nix, `disablePythonPackage`), so it throws when the
# derivation is forced; overriding the function argument the expression
# actually computes `disabled` from sidesteps that, and yields a derivation
# byte-identical to what nixpkgs would produce if it dropped the line.
#
# READING THE RESULT
#
#   all PASS   ->  edit overlays/nomad.nix to the newer interpreter and drop
#                  the paragraph explaining the 3.12 pin.  Consider sending
#                  nixpkgs a PR removing the `disabled` line; link this script
#                  in it.
#   pymatgen FAILS -> the marker is real.  The tail of the build log is
#                  printed; that is the thing to report upstream.
#   pymatgen passes but nomad-lab does not -> pymatgen was never the blocker
#                  on that interpreter.  The error names the package that is.
#
# REQUIREMENTS
#
# A working nix-daemon, and a lot of patience: pymatgen's test suite is long
# and its closure includes numba and vtk.  This CANNOT run inside the Claude
# Code sandbox, which has no daemon — see scripts/no-daemon-check.sh for what
# can.  Nothing here writes outside the nix store.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

interpreters=("$@")
if [[ ${#interpreters[@]} -eq 0 ]]; then
    interpreters=(python313 python314)
fi

# Evaluate against the nixpkgs this repo is locked to, not whatever the
# ambient channel or registry happens to be.  A verdict about a different
# nixpkgs than flake.lock pins would be a verdict about nothing: the whole
# question is whether *our* overlay can move.
if ! command -v jq >/dev/null; then
    echo "jq is required; run this from the devShell (nix develop, or direnv)" >&2
    exit 1
fi

nixpkgs_flake=$(jq -r '
  .nodes.nixpkgs.locked
  | "github:\(.owner)/\(.repo)/\(.rev)"
' flake.lock)

echo "nixpkgs: $nixpkgs_flake"
echo

# One shared preamble for every expression below.  `overlays` is applied so
# that step 3 can reach nomadPython; steps 1 and 2 do not need it but pay
# nothing for it, since the overlay only adds attributes.
preamble="
  let
    pkgs = import (builtins.getFlake \"$nixpkgs_flake\") {
      overlays = builtins.attrValues (import $PWD/overlays);
    };
  in
"

nix_eval() {
    nix eval --impure --raw --expr "$preamble $1"
}

version=$(nix_eval 'pkgs.python312Packages.pymatgen.version')
echo "pymatgen: $version"
echo

failed=0

for interp in "${interpreters[@]}"; do
    echo "=== $interp ==="

    if ! nix_eval "builtins.toString (pkgs ? $interp)" >/dev/null 2>&1; then
        echo "  SKIP: no such interpreter in this nixpkgs"
        echo
        continue
    fi

    # Step 1 — is the marker still there?
    #
    # Read off passthru.disabled, which mk-python-derivation exposes precisely so
    # that this is answerable without forcing the derivation (forcing it is what
    # throws).
    disabled=$(nix_eval "
    let d = pkgs.${interp}Packages.pymatgen.passthru.disabled or false;
    in if d then \"yes\" else \"no\"
  ")

    if [[ $disabled == no ]]; then
        echo "  nixpkgs no longer disables pymatgen here — no workaround needed."
    else
        echo "  nixpkgs disables pymatgen here; building with the marker cleared."
    fi

    # Step 2 — build it, tests and all.
    expr="$preamble (pkgs.${interp}Packages.pymatgen.override { pythonAtLeast = _: false; })"
    if log=$(nix build --impure --no-link --print-out-paths --expr "$expr" 2>&1); then
        echo "  PASS: pymatgen builds and its test suite is green on $interp"
        echo "        ${log##*$'\n'}"
    else
        echo "  FAIL: pymatgen does not build on $interp"
        tail -40 <<<"$log" | sed 's/^/        /'
        failed=1
        echo
        continue
    fi

    # Step 3 — pymatgen is necessary, not sufficient.  Rebuild the scoped
    # package set the overlay would build, but rooted at the candidate
    # interpreter, and instantiate nomad-lab in it.  Instantiating rather than
    # building is the right depth here: the realistic failure is another
    # `disabled` marker or a package that does not exist for this interpreter,
    # and both throw at evaluation.  It takes seconds instead of an afternoon.
    #
    # This mirrors overlays/nomad.nix by construction — if that file grows
    # another argument, this call has to grow it too.
    nomad_expr="$preamble
      ((pkgs.$interp.override {
        self = pkgs.$interp;
        packageOverrides = import $PWD/pkgs/nomad/python-overrides.nix;
      }).pkgs.nomad-lab).drvPath
    "
    if out=$(nix eval --impure --raw --expr "$nomad_expr" 2>&1); then
        echo "  PASS: the nomad-lab closure instantiates on $interp"
        echo "        ${out##*/}"
    else
        echo "  FAIL: pymatgen is fine on $interp but something else is not"
        grep -E '^[[:space:]]*error:[[:space:]]*[^[:space:]]' <<<"$out" | sed 's/^[[:space:]]*/        /'
        failed=1
    fi

    echo
done

if [[ $failed -eq 0 ]]; then
    cat <<'EOF'
VERDICT: the interpreter(s) above are clear.

  1. edit overlays/nomad.nix: change python312 to the newer interpreter and
     delete the paragraph explaining the 3.12 pin;
  2. re-run scripts/no-daemon-check.sh and `just check`;
  3. optionally, open a nixpkgs PR dropping
     `disabled = pythonAtLeast "3.13"` from
     pkgs/development/python-modules/pymatgen/default.nix, citing this run.
EOF
else
    echo "VERDICT: stay on python312. See the failures above."
fi

exit "$failed"
