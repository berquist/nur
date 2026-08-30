# tests/chemtools/default.nix
#
# Evaluation tests for the chemtools and materials overlays.
#
# Run all tests:
#   nix-build tests -A chemtools.all
#
# Run one test:
#   nix-build tests -A chemtools.chemtools-chemfiles-names-do-not-collide
#
# Like ../cheminformatics these build nothing real and need no flake: every
# assertion is about how ../../overlays/default.nix is *wired*, and the verdict
# is baked into the derivation's buildCommand so ../../scripts/no-daemon-check.sh
# can read PASS/FAIL without a daemon.
{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs) lib;

  check =
    name: assertion:
    pkgs.runCommand "test-${name}" { } (
      if assertion then "echo 'PASS: ${name}' && mkdir $out" else "echo 'FAIL: ${name}' >&2 && exit 1"
    );

  ours = import ../../overlays;

  # allowBroken for the same reason ../cheminformatics gives — whether a package
  # is broken should be something to assert, not something that aborts the
  # suite.  Nothing under test here is unfree, so allowUnfree is not needed.
  basePkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = pkgs.config // {
      allowBroken = true;
    };
  };

  overlaidPkgs = basePkgs.extend (
    lib.composeManyExtensions [
      ours.chemtools
      ours.materials
    ]
  );

  # The *whole* stack, exactly as ../../default.nix composes it.
  #
  # Needed because two of the packages here are not isolated from the other
  # overlays: the aiida overlay patches `monty` in the package set — a pandas 3
  # fix, see the `monty` binding in ../../overlays/default.nix — and both
  # custodian and fireworks depend on monty.  So under a partial composition
  # they are built against nixpkgs' monty and under the full one against the
  # patched monty, and comparing the two says nothing about the interpreter pin
  # that the test below is actually about.
  #
  # ../cheminformatics gets away with a partial composition only because none of
  # its packages happens to touch anything the other overlays repair.  That is a
  # coincidence rather than a guarantee, which is why this is spelled out.
  fullyOverlaidPkgs = basePkgs.extend (lib.composeManyExtensions (builtins.attrValues ours));

  # Whether custodian instantiates at all.  See materials-custodian-evaluates
  # below for why this is a binding rather than an inline expression.
  custodianEvaluates = (builtins.tryEval overlaidPkgs.python313Packages.custodian.drvPath).success;

  # Everything the two overlays lift to the top level and ../../default.nix
  # re-exports through python313Packages.  Deliberately not derived from either
  # file — the point is that the hand-written lists agree.
  exportedPackages = [
    "wignernj"
    "strainjedi"
    "sella"
    "molara"
    "custodian"
    "fireworks"
    "qtoolkit"
  ];

  # moltui is deliberately not in the list above.  It is a
  # buildPythonApplication rather than a buildPythonPackage, so it is not a
  # Python module and cannot be a member of any package set — nixpkgs rejects
  # one that turns up in a python313Packages with "moltui should use
  # `buildPythonPackage` or `toPythonModule`".  It is a top-level attribute
  # only, like dotdrop and harmonwig, and gets its own assertions below.
  applicationPackages = [
    "moltui"
  ];

  # Carried for a dependant rather than for their own sake, so they must stay
  # reachable through python313Packages and stay *out* of the top level, or
  # ci.nix builds each of them in its own right.  The materials overlay's only
  # one today: fireworks needs it to test its database code without a database.
  internalDependencies = [
    "mongomock-persistence"
    "pyrr"
  ];

  # `trexio` is deliberately not in that list, because it cannot satisfy it:
  # nixpkgs already has a top-level `trexio` and it is the C library, so
  # "absent from the top level" is not the property to assert.  What must hold
  # is that our binding has not *replaced* it — see chemtools-trexio-* below.

in
lib.fix (self: {
  # ==========================================================================
  # Overlay contract
  # ==========================================================================

  # The top-level aliases and python313Packages must be the same derivation, or
  # every consumer of the overlay builds the closure twice.
  chemtools-toplevel-packages = check "chemtools-toplevel-packages" (
    lib.all (
      name: overlaidPkgs ? ${name} && overlaidPkgs.${name} == overlaidPkgs.python313Packages.${name}
    ) exportedPackages
  );

  # The interpreter is spelled out twice — `py` in ../../default.nix and the
  # top-level `inherit` in ../../overlays/default.nix — and nothing forces the
  # two to agree.
  #
  # Against fullyOverlaidPkgs rather than overlaidPkgs, for the monty reason
  # given at that binding: ../../default.nix composes every overlay, so this has
  # to as well or it compares two differently-built custodians and fails for a
  # reason that has nothing to do with the pin.
  chemtools-python-pin = check "chemtools-python-pin" (
    let
      nur = import ../../default.nix { pkgs = basePkgs; };
    in
    lib.all (name: nur ? ${name} && nur.${name} == fullyOverlaidPkgs.${name}) exportedPackages
  );

  # The applications are top-level attributes and must stay *out* of the Python
  # package set.  Putting one in is not a style slip — it is an eval error that
  # takes the whole overlay down, which is how moltui was caught in the first
  # place — so this asserts the shape rather than trusting it.
  chemtools-applications-are-toplevel-only = check "chemtools-applications-are-toplevel-only" (
    lib.all (
      name: overlaidPkgs ? ${name} && !(overlaidPkgs.python313Packages ? ${name})
    ) applicationPackages
  );

  # ...and ../../default.nix must re-export the same derivation, the way it does
  # for dotdrop and harmonwig.
  chemtools-applications-match-nur = check "chemtools-applications-match-nur" (
    let
      nur = import ../../default.nix { pkgs = basePkgs; };
    in
    lib.all (name: nur ? ${name} && nur.${name} == fullyOverlaidPkgs.${name}) applicationPackages
  );

  # Dependencies stay reachable but stay out of the top level.  The mirror of
  # cheminformatics-dependencies-are-internal in ../cheminformatics.
  chemtools-dependencies-are-internal = check "chemtools-dependencies-are-internal" (
    lib.all (
      name: overlaidPkgs.python313Packages ? ${name} && !(overlaidPkgs ? ${name})
    ) internalDependencies
  );

  # ==========================================================================
  # The trexio name split
  # ==========================================================================

  # nixpkgs' top-level `trexio` is the C library; ../../pkgs/trexio is the SWIG
  # binding, and both want the name.  The binding lives only in the package
  # sets, so the top-level attribute must still be the library — a `trexio`
  # there carrying `pythonModule` means the extension leaked upward and every
  # consumer of this overlay just lost the C library.
  #
  # The mirror of the chemfiles split below, and the more dangerous direction of
  # it: chemfiles collides with a name *we* introduce, whereas this one would
  # quietly redefine an attribute nixpkgs already ships.
  chemtools-trexio-toplevel-is-the-c-library = check "chemtools-trexio-toplevel-is-the-c-library" (
    !(overlaidPkgs.trexio ? pythonModule)
  );

  chemtools-trexio-binding-is-separate = check "chemtools-trexio-binding-is-separate" (
    overlaidPkgs.python313Packages.trexio ? pythonModule
    && overlaidPkgs.python313Packages.trexio != overlaidPkgs.trexio
  );

  # ==========================================================================
  # The chemfiles name split
  # ==========================================================================

  # `chemfiles` means two different things and both have to keep working:
  # the top-level attribute is the C++ shared library, and the Python attribute
  # is the binding.  This is the test that earns its keep, because the failure
  # is a silent infinite recursion or a silently wrong dependency rather than a
  # missing attribute — a python-set callPackage resolves the *Python*
  # `chemfiles` before falling back to the top level, so a derivation taking a
  # defaulted `chemfiles` argument would bind to itself.
  chemtools-chemfiles-names-do-not-collide = check "chemtools-chemfiles-names-do-not-collide" (
    # The top-level one is not a Python package...
    !(overlaidPkgs.chemfiles ? pythonModule)
    # ...and the Python one is.
    && overlaidPkgs.python313Packages.chemfiles ? pythonModule
    # And they are genuinely different derivations.
    && overlaidPkgs.chemfiles != overlaidPkgs.python313Packages.chemfiles
  );

  # The binding must build against *our* chemfiles rather than vendoring its
  # git submodule.  If this ever stops holding, the package still imports and
  # still passes its tests — it just ships a second private copy of the library
  # — so nothing but an assertion catches it.
  chemtools-chemfiles-binding-uses-our-library = check "chemtools-chemfiles-binding-uses-our-library" (
    lib.elem overlaidPkgs.chemfiles overlaidPkgs.python313Packages.chemfiles.buildInputs
  );

  # ==========================================================================
  # The shared pymatgen lift
  # ==========================================================================

  # `pymatgenFor` repairs pymatgen for the aiida and materials overlays, and it
  # must stay a `let` binding: injecting it into the package set would silently
  # change pymatgen for everything else in a consumer's set.  nixpkgs gates
  # pymatgen off 3.13 with `disabled = pythonAtLeast "3.13"`, and a gated
  # package throws on instantiation — so the set's own attribute still refusing
  # to evaluate is the evidence that the repair stayed local.
  #
  # The mirror of aiida-overlay-pymatgen-override-is-local in ../aiida, for the
  # second consumer of the same binding, and deliberately spelled the same way.
  materials-pymatgen-override-is-local = check "materials-pymatgen-override-is-local" (
    !(builtins.tryEval overlaidPkgs.python313Packages.pymatgen.drvPath).success
  );

  # ...while custodian, which needs it lifted, still evaluates.  Without the
  # shared binding this throws rather than fails.
  #
  # Bound in the `let` above rather than inline: statix rejects parentheses
  # around a bare select expression, and without them the assertion does not fit
  # on one line.
  materials-custodian-evaluates = check "materials-custodian-evaluates" custodianEvaluates;

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "chemtools-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
