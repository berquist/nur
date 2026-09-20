# update-universe.nix — every package this repository defines, with the
# attribute path something can point `nix-update` at, and the update policy that
# applies to it.
#
#   ./scripts/sandbox-eval.sh --json 'import ./scripts/update-universe.nix { }'
#   ./scripts/sandbox-eval.sh --json \
#       'import ./scripts/update-universe.nix { only = [ "qcportal" ]; }'
#
# The second form is seconds where the first is minutes; see the `only`
# argument.  `just update-policy` runs the first, and scripts/update-packages.sh
# passes whatever was named on its command line as `only`.
#
# This is the input to scripts/update-packages.sh and the only place the policy
# rule of docs/version-updates.md §4 is written down.  Nothing here is a
# hand-maintained package list: the attribute paths come from ../default.nix,
# and `missing` below is what keeps that from silently drifting away from the
# directories on disk.
#
# **`missing` being non-empty is a bug, not a warning.**  A package in ../pkgs
# with no attribute path is a package the updater cannot see, and the whole
# reason to key this off `builtins.readDir` rather than off the attribute set is
# to make that loud.  `graphrc` was exactly that case until ../flake.nix started
# exposing it; see the note there.
#
# Metadata only — `version`, `meta.position`, `meta.broken`, and the declared
# `passthru.updatePolicy`.  `drvPath` is never forced, so the broken members and
# the one unfree member are safe to enumerate.  Each read is still wrapped in
# `tryEval`: `tensorpotential` is unfree and a package can be null-or-throwing on
# a channel missing e3nn or warp-lang, and a tool that enumerates the universe
# must not be the thing that dies of it.

{
  pkgs ? import <nixpkgs> { },
  # Resolve only these attribute paths, skipping the coverage check.
  #
  # The whole-universe walk is not cheap: `lib.isDerivation` forces every
  # top-level attribute, which is an evaluation of the entire overlaid package
  # set, and that is minutes rather than seconds.  Paying it to answer a
  # question about one package — `just update-scan qcportal` — is the wrong
  # trade, so a named subset is looked up directly instead.
  #
  # `missing` is then empty by construction rather than by verification.  That
  # is sound because the check it stands in for is about the *set* of packages,
  # which a subset run is not asking about; the full run is still the one that
  # guarantees coverage.
  only ? [ ],
}:

let
  inherit (pkgs) lib;

  nur = import ../. { inherit pkgs; };

  # The same composition ../default.nix performs, needed for `graphrc` alone:
  # it is a top-level attribute of overlays.cheminformatics-cclib rather than a
  # member of any Python set, and ../default.nix deliberately does not
  # re-export it.  Everything else below comes from `nur`.
  pkgs' = pkgs.extend (lib.composeManyExtensions (builtins.attrValues (import ../overlays)));

  # Keep in sync with the predicate in ../overlay.nix.  `internalPackages` is
  # reserved there and is descended into here, which is the same asymmetry
  # ../ci.nix carries and for the same reason.
  reserved = [
    "lib"
    "overlays"
    "nixosModules"
    "homeModules"
    "darwinModules"
    "flakeModules"
    "python3Packages"
    "internalPackages"
  ];

  topLevel = lib.filterAttrs (n: v: !(builtins.elem n reserved) && lib.isDerivation v) nur;

  internal = lib.mapAttrs' (n: lib.nameValuePair "internalPackages.${n}") (
    lib.filterAttrs (_: lib.isDerivation) nur.internalPackages
  );

  # The seven packages ../default.nix names but does not expose at the top
  # level, each for a reason given at its own note there.  Spelled out rather
  # than discovered, because the whole 3.13 set cannot be enumerated and these
  # are bounded: two name collisions, one unfree package, and four guarded
  # backports.
  extras = {
    "internalPackages.chemfiles" = nur.internalPackages.chemfiles;
    "internalPackages.trexio" = nur.internalPackages.trexio;
    "python3Packages.monty" = nur.python3Packages.monty;
    "python3Packages.pycifrw" = nur.python3Packages.pycifrw;
    "python3Packages.qcelemental" = nur.python3Packages.qcelemental;
    "python3Packages.qcengine" = nur.python3Packages.qcengine;
    "python3Packages.tensorpotential" = nur.python3Packages.tensorpotential;
    # Reachable as `nix build .#graphrc` only — see ../flake.nix.
    inherit (pkgs') graphrc;
  };

  everything = topLevel // internal // extras;

  # One attribute path, without forcing its neighbours.  `extras` is consulted
  # first because its keys are dotted strings in their own right; anything else
  # is a path into `nur`.  Constructing `extras` forces no value, so the
  # membership test is free even for `graphrc`, which would otherwise drag in a
  # second package-set composition.
  lookup = path: extras.${path} or (lib.getAttrFromPath (lib.splitString "." path) nur);

  candidates = if only == [ ] then everything else lib.genAttrs only lookup;

  # ../pkgs, as a string, so a position can be tested against it by prefix
  # rather than by regex.  Prefix rather than a `.*/pkgs/` match on purpose:
  # nixpkgs' own positions are under *its* pkgs/ and would match that happily,
  # which is how a package overridden onto a nixpkgs derivation — `monty` and
  # `pycifrw` on a new enough channel — gets correctly reported as external.
  pkgsDir = "${toString ../pkgs}/";
  pkgsDirLength = builtins.stringLength pkgsDir;

  directoryOf =
    position:
    if position == null then
      null
    else if builtins.substring 0 pkgsDirLength position != pkgsDir then
      null
    else
      builtins.head (lib.splitString "/" (builtins.substring pkgsDirLength (-1) position));

  # `version` carries the `X.Y.Z-unstable-YYYY-MM-DD` marker for a package
  # pinned to a commit rather than a tag, which is what decides branch mode.
  followsBranch = version: version != null && lib.hasInfix "-unstable-" version;

  read =
    drv:
    let
      raw = {
        version = drv.version or null;
        position = drv.meta.position or null;
        broken = drv.meta.broken or false;
        declared = drv.updatePolicy or null;
      };
      probe = builtins.tryEval (builtins.deepSeq raw raw);
    in
    if probe.success then
      probe.value
    else
      {
        version = null;
        position = null;
        broken = true;
        declared = {
          mode = "report";
          reason = "metadata does not evaluate on this channel — unfree, or a missing dependency";
        };
      };

  describe =
    attr: drv:
    let
      got = read drv;
      declared = if got.declared == null then { } else got.declared;
      directory = directoryOf got.position;

      # docs/version-updates.md §4: infer the rule, declare the exception.  A
      # broken package is inferred into `report` rather than `stable` because
      # `nix-update --build` would fail on it for a reason that has nothing to
      # do with the bump, and a failure the bot cannot interpret is worse than
      # a line in the report.
      inferred =
        if got.broken then
          "report"
        else if followsBranch got.version then
          "branch"
        else
          "stable";
    in
    {
      inherit attr directory;
      inherit (got) version broken position;
      # `external` overrides a declared mode as well as the inferred one, and
      # has to: the attribute resolves to a derivation defined outside ../pkgs,
      # so the file `nix-update` would rewrite is nixpkgs' own — in the store,
      # and not ours to touch.  `pycifrw`, `monty`, `qcelemental` and `qcengine`
      # are the guarded backports this is for; on a channel new enough to carry
      # them, ../overlays leaves nixpkgs' derivation in place and there is
      # nothing here to update.
      mode = if directory == null then "external" else declared.mode or inferred;
      inferredMode = inferred;
      declaredMode = declared.mode or null;
      reason = declared.reason or null;
      # `--version=branch=<name>` where a package deliberately follows something
      # other than its repository's default branch.  Nothing declares one today.
      branch = declared.branch or null;
      # `--version-regex`, for a repository whose tags do not spell a version on
      # their own.  The four fairchem distributions are the case that forced it:
      # they share one monorepo which tags each separately, so every one of them
      # is offered all four tag series and `nix-update` cannot parse any of them
      # as a version.  The regex names the series this attribute belongs to, and
      # its one capture group is the version inside the tag.  It applies in
      # branch mode too — a snapshot's `X-unstable-<date>` prefix comes from the
      # same release feed.
      #
      # Declaring it also switches the driver to the paginated releases API, for
      # a reason given at `nix_update_argv` in ../scripts/update-packages.sh: a
      # repository with several series is exactly one whose newest-few-releases
      # feed may not mention yours.
      versionRegex = declared.versionRegex or null;
      # The attribute whose bump carries this one — `dpdata-plugin-test` builds
      # from ../pkgs/dpdata's `src` one directory down and has no version of its
      # own.  Reported, never acted on.
      follows = declared.follows or null;
      # A second fetch in the same derivation, and what to do about it.  See
      # docs/version-updates.md and the seven packages that declare one.
      secondary = declared.secondary or null;
    };

  packages = lib.mapAttrs describe candidates;

  entries = builtins.attrValues packages;

  # The coverage check, and the reason this file reads the directory at all.
  onDisk = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../pkgs)
  );
  covered = lib.unique (builtins.filter (d: d != null) (map (e: e.directory) entries));

  externalEntries = builtins.filter (e: e.mode == "external") entries;

  # A directory whose package *is* reachable, but whose attribute resolves to
  # nixpkgs' derivation rather than ours.  That is the guarded backport working
  # as designed — ../pkgs/monty, ../pkgs/pycifrw, ../pkgs/qcelemental and
  # ../pkgs/qcengine all say so at their headers — and it must not be confused
  # with a directory nothing can reach.  Matched on the attribute's last
  # component, which is the distribution name and so the directory name too.
  shadowed = lib.unique (
    builtins.filter (d: builtins.elem d onDisk) (
      map (e: lib.last (lib.splitString "." e.attr)) externalEntries
    )
  );

  modes = lib.unique (map (e: e.mode) entries);
in
{
  inherit packages shadowed;

  # Whether this answer covers the whole repository, so the driver can tell
  # "nothing is missing" from "nothing was looked at".
  complete = only == [ ];

  # Empty, or the driver refuses to run.  See the header, and the `only`
  # argument for why a subset run cannot answer this.
  missing = if only == [ ] then lib.subtractLists (covered ++ shadowed) onDisk else [ ];

  # Reported alongside `missing` because the two are different failures: a
  # directory with no attribute path at all, versus an attribute path whose
  # position is not under ../pkgs — correct for a guarded backport, and a bug
  # for anything else, which is why both lists are printed rather than summed.
  external = map (e: e.attr) externalEntries;

  counts = {
    total = builtins.length entries;
    directories = builtins.length onDisk;
    byMode = lib.listToAttrs (
      map (m: lib.nameValuePair m (builtins.length (builtins.filter (e: e.mode == m) entries))) modes
    );
  };
}
