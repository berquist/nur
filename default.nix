# default.nix
#
# NUR entry point. Applies our overlays to a local pkgs' so that:
#   nix-build -A qcportal                works
#   nix-build -A qcfractal               works
#   python313.withPackages (p: [...])    works (same store paths, no duplication)
#
# overlay.nix (the NUR template file) derives itself from this file by
# filtering reserved names, so it continues to work unchanged.

{
  pkgs ? import <nixpkgs> { },
}:

let
  overlays = import ./overlays;

  # Compose all overlays in overlays/ into one and apply it.
  pkgs' = pkgs.extend (pkgs.lib.composeManyExtensions (builtins.attrValues overlays));

  # Pinned rather than python3Packages: nixpkgs-unstable has moved python3 to
  # 3.14, where qcportal cannot even be imported (see pkgs/qcportal/default.nix
  # for the qcelemental mechanism).  Following the default interpreter would
  # mean this repo ships nothing at all on unstable, and would take every VM
  # test in `nix flake check` down with it the moment flake.lock is bumped past
  # the switch.  Revert to python3Packages once upstream releases its pydantic
  # v2 migration.
  #
  # Keep in sync with the top-level aliases in overlays/default.nix; the
  # overlay-python-pin eval test asserts the two agree.
  py = pkgs'.python313Packages;
in
{
  # Reserved keys — not lifted into the nixpkgs overlay by overlay.nix.
  nixosModules = import ./nixos-modules;
  inherit overlays;

  # The overlaid 3.13 package set, exposed so that the twenty-odd dependencies
  # this repo carries but does not re-export at the top level — mdanalysis,
  # griddataformats, lwreg, kiwipy, plumpy and the rest — have an attribute path
  # something can point at:
  #
  #   nix run nixpkgs#nix-update -- --flake python313Packages.mdanalysis
  #
  # Without it those packages are reachable only from inside a derivation, and
  # nothing can be automated against them.
  #
  # **Reserved, and it must stay that way.**  Lifting a `python313Packages` key
  # into a nixpkgs overlay would replace the consumer's own python313Packages
  # with this one — computed from *our* pkgs', with our overlays already baked
  # in.  The isReserved predicate is spelled out in both ./overlay.nix and
  # ./ci.nix; adding a reserved key means editing both.
  #
  # dontRecurseIntoAttrs is the other half.  This is the *whole* 3.13 set, some
  # ten thousand packages, and both `nix-env -f . -qa '*'` (what `just ci-eval`
  # runs) and ci.nix's flattenPkgs descend into an attrset only when it carries
  # recurseForDerivations.  Clearing it keeps a named lookup working while
  # keeping every traversal out — otherwise CI would try to build all of
  # nixpkgs' Python packages, and the eval pass would force the broken ones.
  python313Packages = pkgs'.lib.dontRecurseIntoAttrs py;

  # Python *applications*: reached through the overlay rather than
  # callPackage'd here, so that pkgs.dotdrop and this attribute are the same
  # derivation.  Built against the default python3, not the 3.13 pin below.
  #
  # harmonwig is here too, but on the bare NUR path it carries meta.broken:
  # its cclib comes from a flake input that ./overlays cannot reach.  See
  # pkgs/harmonwig/default.nix, and flake.nix for the working instantiation.
  #
  # moltui is a third: a TUI application rather than a library, so it is a
  # buildPythonApplication and could not sit in python313Packages even if the
  # pin were wanted — nixpkgs rejects a non-module in a Python package set.
  inherit (pkgs') dotdrop harmonwig moltui;

  # The cheminformatics packages that need cclib.  Same arrangement as
  # harmonwig above and for the same reason — see overlays/default.nix's
  # cheminformatics-cclib — so on the bare NUR path all four carry meta.broken
  # and only `nix build .#<name>` produces something usable.
  inherit (pkgs')
    aqme
    ccreg
    dbstep
    digichem-core
    metallogen
    molcat
    ;

  # The chemfiles C++ library.  Not a Python package, so it comes straight from
  # the overlaid set rather than through `py` below — and pkgs/chemfiles-python
  # binds against exactly this derivation.
  #
  # There is deliberately no top-level alias for the *Python* binding, which is
  # also called `chemfiles`: one name cannot be both, and this is the split both
  # halves of the audience expect.  `pkgs.chemfiles` is the shared library, the
  # way every other distribution spells it; `python313Packages.chemfiles` is the
  # module, the way pip spells it.  See the callPackage site in
  # overlays/default.nix for how the two are kept from resolving to each other.
  inherit (pkgs') chemfiles;

  # Python packages, reached through the extended python313Packages so that
  # these derivations are identical to what python313.withPackages returns.
  inherit (py)
    parsl
    qcportal
    qcfractal
    qcfractalcompute
    qcarchivetesting

    aiida-core
    aiida-cp2k
    aiida-gaussian
    aiida-octopus
    aiida-orca
    aiida-psi4
    aiida-quantumespresso

    morfeus-ml
    qmzyme
    dough

    wignernj
    strainjedi
    sella

    custodian
    fireworks
    ;
}
