# This file provides all the buildable and cacheable packages and
# package outputs in your package set. These are what gets built by CI,
# so if you correctly mark packages as
#
# - broken (using `meta.broken`),
# - unfree (using `meta.license.free`), and
# - locally built (using `preferLocalBuild`)
#
# then your CI will be able to build and cache only those packages for
# which this is possible.

{
  pkgs ? import <nixpkgs> { },
}:

with builtins;
let
  # Keep in sync with the same predicate in ./overlay.nix.
  #
  # python313Packages is the whole 3.13 set, exposed so that nix-update can
  # reach the dependencies ./default.nix does not re-export.  It carries
  # dontRecurseIntoAttrs, so flattenPkgs below would skip it anyway; naming it
  # here says so on purpose rather than by accident.
  isReserved =
    n:
    n == "lib"
    || n == "overlays"
    || n == "nixosModules"
    || n == "homeModules"
    || n == "darwinModules"
    || n == "flakeModules"
    || n == "python313Packages";
  isDerivation = p: isAttrs p && p ? type && p.type == "derivation";

  # Two halves, and the second one is not what it looks like.
  #
  # `meta.broken` is the ordinary case.  The licence half is the same mechanism
  # wearing a different message:
  #
  #   error: Refusing to evaluate package '...' because it has an unfree license
  #
  # That is an *evaluation* error, not a build failure.  `cacheOutputs` is what
  # `just ci-build` forces, nothing in the Justfile or .github/workflows sets
  # allowUnfree, and `--keep-going` has no bearing on eval.  So one unfree
  # attribute does not cost one package — it costs the whole cache-population
  # build, unattempted.  flake.nix's `packages` block declines to name such an
  # attribute for exactly the same reason.
  #
  # Since molcat was removed this half matches nothing: every top-level
  # attribute of ./default.nix is free.  It stays as a guard rather than going
  # as dead code because the input recurs — molcat was an unremarkable academic
  # log parser published with no LICENSE file at all, and `lib.licenses.unfree`
  # is the accurate spelling of that.
  #
  # Its reach is narrow, though, and worth knowing before relying on it: this
  # reads the licence of top-level attributes of ./default.nix and nothing else.
  # An unfree *dependency* throws just the same and is not caught here, and
  # neither the VM tests nor `just ci-eval` come through this file at all.
  isBuildable =
    p:
    let
      licenseFromMeta = p.meta.license or [ ];
      licenseList = if builtins.isList licenseFromMeta then licenseFromMeta else [ licenseFromMeta ];
    in
    !(p.meta.broken or false) && builtins.all (license: license.free or true) licenseList;
  isCacheable = p: !(p.preferLocalBuild or false);
  shouldRecurseForDerivations = p: isAttrs p && p.recurseForDerivations or false;

  nameValuePair = n: v: {
    name = n;
    value = v;
  };

  concatMap = builtins.concatMap or (f: xs: concatLists (map f xs));

  flattenPkgs =
    s:
    let
      f =
        p:
        if shouldRecurseForDerivations p then
          flattenPkgs p
        else if isDerivation p then
          [ p ]
        else
          [ ];
    in
    concatMap f (attrValues s);

  outputsOf = p: map (o: p.${o}) p.outputs;

  nurAttrs = import ./default.nix { inherit pkgs; };

  nurPkgs = flattenPkgs (
    listToAttrs (
      map (n: nameValuePair n nurAttrs.${n}) (filter (n: !isReserved n) (attrNames nurAttrs))
    )
  );

in
rec {
  buildPkgs = filter isBuildable nurPkgs;
  cachePkgs = filter isCacheable buildPkgs;

  buildOutputs = concatMap outputsOf buildPkgs;
  cacheOutputs = concatMap outputsOf cachePkgs;
}
