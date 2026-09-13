# tests/cheminformatics/default.nix
#
# Evaluation tests for the two cheminformatics overlays.
#
# Run all tests:
#   nix-build tests -A cheminformatics.all
#
# Run one test:
#   nix-build tests -A cheminformatics.cheminformatics-cclib-resolves
#
# Unlike ../harmonwig/default.nix these build nothing real and need no flake:
# every assertion is about how ../../overlays/default.nix is *wired*, and the
# verdict is baked into the derivation's buildCommand so that
# ../../scripts/no-daemon-check.sh can read PASS/FAIL without a daemon — the
# same arrangement as ../qcarchive and ../aiida.
#
# That is exactly the reach these need.  The cclib dependants here cannot be
# built from this file, but the mistakes worth catching are wiring mistakes,
# and every one of them is silent: a `cclib ? null` argument that goes
# unresolved produces a package that is meta.broken with nothing to say why.

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

  # nixpkgs' checkMeta throws on any attribute access to a broken derivation,
  # and four of the six packages under test are broken by design here.  Rather
  # than tiptoe around that, every set below allows broken packages; whether a
  # package *is* broken is then something to assert rather than something that
  # aborts the suite.
  #
  # Re-imported from `pkgs.path` with `pkgs.config` carried over, rather than
  # from <nixpkgs>, so that a caller passing its own package set still gets that
  # set's nixpkgs and configuration.
  basePkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = pkgs.config // {
      allowBroken = true;
    };
  };

  overlaidPkgs = basePkgs.extend (
    lib.composeManyExtensions [
      ours.cheminformatics
      ours.cheminformatics-cclib
      ours.harmonwig
    ]
  );

  # A stand-in for cclib's own overlay, reproducing the one thing about its
  # shape that matters here: it overrides the top-level `python3` attribute
  # through `packageOverrides`, and touches nothing else.  See
  # https://github.com/cclib/cclib nix/overlay.nix, and the cclib input in
  # ../../flake.nix.
  #
  # numpy stands in for the cclib derivation itself.  Nothing here builds, and
  # what is being tested is whether `callPackage` finds *something* under the
  # name `cclib` in the set the overlays reach for — which is the whole of the
  # bug this file exists to catch.
  cclibStubOverlay = _final: prev: {
    python3 = prev.python3.override (old: {
      packageOverrides = lib.composeExtensions (old.packageOverrides or (_: _: { })) (
        _pfinal: pprev: {
          cclib = pprev.numpy;
        }
      );
    });
  };

  cclibPkgs = basePkgs.extend (
    lib.composeManyExtensions [
      cclibStubOverlay
      ours.cheminformatics
      ours.cheminformatics-cclib
      ours.harmonwig
    ]
  );

  # Everything the cheminformatics overlay lifts to the top level and
  # ../../default.nix re-exports through python313Packages.  Deliberately not
  # derived from either file — the point is that the hand-written lists agree.
  exportedPackages = [
    "dough"
    "morfeus-ml"
    "qmzyme"
  ];

  # The packages that take a `cclib ? null` argument and carry meta.broken when
  # it goes unfilled.  aiida-gaussian is absent: it is a member of the aiida
  # overlay rather than either of these two, and ../aiida/default.nix covers it.
  cclibPackages = [
    "aqme"
    "ccreg"
    "dbstep"
    "digichem-core"
    "harmonwig"
    "metallogen"
    "xyzrender"
  ];

  # graphrc is the one cclib package that is *not* in the list above, because it
  # is not re-exported: cclib forces it to be a top-level attribute of the
  # overlay, while nothing but xyzrender wants it.  It therefore has to satisfy
  # both halves of a contradiction — present in overlaidPkgs, absent from
  # ../../default.nix — which cheminformatics-graphrc-is-not-re-exported below
  # is the only thing checking.
  cclibDependencies = [
    "graphrc"
  ];

  # The dependencies that stop at the pythonPackagesExtensions step: reachable
  # through python313Packages, never top-level attributes, so that ci.nix does
  # not build each of them in its own right.
  internalDependencies = [
    "basis-set-exchange"
    "colour-science"
    "configurables"
    "griddataformats"
    "lwreg"
    "mda-xdrlib"
    "mdanalysis"
    "mrcfile"
    "openprattle"
    "xyzgraph"
  ];

in
lib.fix (self: {
  # ==========================================================================
  # Overlay contract
  # ==========================================================================

  # The top-level aliases and python313Packages must be the same derivation,
  # or every consumer of the overlay builds the closure twice.
  cheminformatics-toplevel-packages = check "cheminformatics-toplevel-packages" (
    lib.all (
      name: overlaidPkgs ? ${name} && overlaidPkgs.${name} == overlaidPkgs.python313Packages.${name}
    ) exportedPackages
  );

  # The interpreter is spelled out twice — `py` in ../../default.nix and the
  # top-level `inherit` in ../../overlays/default.nix — and nothing forces the
  # two to agree.
  cheminformatics-python-pin = check "cheminformatics-python-pin" (
    let
      nur = import ../../default.nix { pkgs = basePkgs; };
    in
    lib.all (name: nur ? ${name} && nur.${name} == overlaidPkgs.${name}) exportedPackages
  );

  # Dependencies stay reachable but stay out of the top level.
  cheminformatics-dependencies-are-internal = check "cheminformatics-dependencies-are-internal" (
    lib.all (
      name: overlaidPkgs.python313Packages ? ${name} && !(overlaidPkgs ? ${name})
    ) internalDependencies
  );

  # The rdkit repair in ../../overlays/default.nix has to land in every package
  # set a dependant is built from, and it fails silently if it does not: the
  # unrepaired rdkit builds and imports perfectly, so nothing goes wrong until
  # some dependant's pythonRuntimeDepsCheck says "rdkit not installed" — at
  # build time, for a reason that points at the wrong package.
  #
  # Three sets rather than one, because the dependants disagree about where
  # they look.  qmzyme finds rdkit through python313Packages; aqme and
  # digichem-core are `final.python3.pkgs.callPackage`s, and on the flake path
  # that is the set cclib's overlay has rebuilt — the same "which set am I in"
  # trap the cclib tests below exist for.
  #
  # Asserting on postInstall rather than comparing derivations: rdkit differs
  # between these sets anyway, because they do not all share an interpreter, so
  # an inequality would pass whether the repair applied or not.
  cheminformatics-rdkit-repair-applies = check "cheminformatics-rdkit-repair-applies" (
    lib.all (set: lib.hasInfix ".dist-info" (set.rdkit.postInstall or "")) [
      overlaidPkgs.python313Packages
      overlaidPkgs.python3.pkgs
      cclibPkgs.python3.pkgs
    ]
  );

  # ==========================================================================
  # The cclib split
  # ==========================================================================

  # Without cclib every dependant must say so, because that is what keeps
  # ci.nix and `just ci-build` from trying to build something that cannot work.
  cheminformatics-cclib-broken-without-cclib = check "cheminformatics-cclib-broken-without-cclib" (
    lib.all (name: overlaidPkgs.${name}.meta.broken or false) cclibPackages
  );

  # ...and with cclib present, every one of them must stop saying so.
  #
  # This is the test that earns its keep.  These packages take cclib as a
  # defaulted argument, so a `callPackage` reaching into the wrong package set
  # does not fail — it quietly passes null and produces a permanently broken
  # package.  That is not hypothetical: `final.python3Packages` looks like the
  # right spelling and is not, because nixpkgs defines it as an alias to
  # python314Packages rather than as `python3.pkgs`, and cclib's overlay
  # overrides `python3`.  Nothing but an assertion catches that.
  cheminformatics-cclib-resolves = check "cheminformatics-cclib-resolves" (
    lib.all (name: !(cclibPkgs.${name}.meta.broken or false)) cclibPackages
  );

  # The cclib dependencies get both halves of the same treatment, since they are
  # built the same way and would break in the same silent manner.
  cheminformatics-cclib-dependencies-resolve = check "cheminformatics-cclib-dependencies-resolve" (
    lib.all (
      name: (overlaidPkgs.${name}.meta.broken or false) && !(cclibPkgs.${name}.meta.broken or false)
    ) cclibDependencies
  );

  # ...but unlike the packages above they must not reach ../../default.nix, or
  # ci.nix builds a dependency as though it were a product.  The pair of
  # conditions is the whole point: "top-level in the overlay" and "absent from
  # the NUR attrset" are individually unremarkable and jointly the contract.
  cheminformatics-graphrc-is-not-re-exported = check "cheminformatics-graphrc-is-not-re-exported" (
    let
      nur = import ../../default.nix { pkgs = basePkgs; };
    in
    lib.all (name: (overlaidPkgs ? ${name}) && !(nur ? ${name})) cclibDependencies
  );

  # ==========================================================================
  # Convenience target: every test above, built at once.
  # ==========================================================================
  all = pkgs.symlinkJoin {
    name = "cheminformatics-tests";
    paths = lib.attrValues (removeAttrs self [ "all" ]);
  };
})
