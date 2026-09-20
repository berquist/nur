# default.nix
#
# NUR entry point. Applies our overlays to a local pkgs' so that:
#   nix-build -A qcportal                works
#   nix-build -A qcfractal               works
#   python3.withPackages (p: [...])      works (same store paths, no duplication)
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

  # The channel's default interpreter, deliberately, and not a pinned version.
  # This was `python313Packages` for as long as qcportal was pydantic v1: on
  # 3.14 qcelemental replaces every QCSchema v1 name with a placeholder and
  # qcportal could not be imported at all, so following the default would have
  # meant shipping no QCArchive half on unstable.  qcportal 0.70 is pydantic v2
  # and the gate is gone; see pkgs/qcportal/default.nix.
  #
  # What following the default means in practice: **the CI matrix now spans two
  # interpreters, where the pin gave it one.**  nixpkgs-unstable and
  # nixos-unstable are 3.14.7; nixos-26.05 is 3.13.15.  A channel that moves its
  # python3 moves this repository with it, and nothing here names a version for
  # that to disagree with.
  #
  # So a per-interpreter failure is now a *per-leg* failure, and `just ci
  # nixos-26.05` is no longer the same build as `just ci nixpkgs-unstable` with
  # older dependencies — it is a different interpreter as well.  pkgs/aiida-psi4
  # is the worked example: `broken = pythonAtLeast "3.14"` means it builds on
  # the 26.05 leg and is skipped on the other two.  That is the shape to expect
  # from anything else 3.14 turns out to break — mark it, do not re-pin.
  #
  # Keep in sync with the top-level aliases in overlays/default.nix; the
  # overlay-python-pin eval test asserts the two agree.
  py = pkgs'.python3Packages;
in
{
  # Reserved keys — not lifted into the nixpkgs overlay by overlay.nix.
  nixosModules = import ./nixos-modules;
  inherit overlays;

  # The overlaid default package set, exposed so that the twenty-odd
  # dependencies this repo carries but does not re-export at the top level —
  # mdanalysis, griddataformats, lwreg, kiwipy and the rest — have an attribute
  # path something can point at:
  #
  #   nix run nixpkgs#nix-update -- --flake python3Packages.mdanalysis
  #
  # Without it those packages are reachable only from inside a derivation, and
  # nothing can be automated against them.
  #
  # **Reserved, and it must stay that way.**  Lifting a `python3Packages` key
  # into a nixpkgs overlay would replace the consumer's own python3Packages
  # with this one — computed from *our* pkgs', with our overlays already baked
  # in.  The isReserved predicate is spelled out in both ./overlay.nix and
  # ./ci.nix; adding a reserved key means editing both.
  #
  # dontRecurseIntoAttrs is the other half.  This is the *whole* default set,
  # some ten thousand packages, and both `nix-env -f . -qa '*'` (what `just
  # ci-eval` runs) and ci.nix's flattenPkgs descend into an attrset only when it
  # carries recurseForDerivations.  Clearing it keeps a named lookup working
  # while keeping every traversal out — otherwise CI would try to build all of
  # nixpkgs' Python packages, and the eval pass would force the broken ones.
  python3Packages = pkgs'.lib.dontRecurseIntoAttrs py;

  # Python *applications*: reached through the overlay rather than
  # callPackage'd here, so that pkgs.dotdrop and this attribute are the same
  # derivation.  They are applications rather than modules, which is why they
  # are top-level attributes instead of members of `py` below — nixpkgs rejects
  # a non-module in a Python package set.
  #
  # harmonwig is here too, but on the bare NUR path it carries meta.broken:
  # its cclib comes from a flake input that ./overlays cannot reach.  See
  # pkgs/harmonwig/default.nix, and flake.nix for the working instantiation.
  # It is also the one of the three built from `final.python3.pkgs` rather than
  # `final.python3Packages`, which is not the same set once cclib's overlay has
  # rebuilt python3; see the note at that callPackage in overlays/default.nix.
  inherit (pkgs') dotdrop harmonwig moltui;

  # anilist-mal-sync: a Go CLI, not Python at all, reached through the
  # overlay for the same reason as the three above — see
  # overlays/default.nix's anilist-mal-sync entry. Also what lets
  # nixos-modules/anilist-mal-sync.nix resolve it via
  # `lib.mkPackageOption pkgs "anilist-mal-sync"`.
  inherit (pkgs') anilist-mal-sync;

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
    xyzrender
    ;
  # graphrc is deliberately absent from that list.  It is a top-level attribute
  # of overlays.cheminformatics-cclib only because cclib forces it to be — see
  # the note at that binding — and it exists for xyzrender alone, so
  # re-exporting it here would have ci.nix build it as a package in its own
  # right.

  # The chemfiles C++ library.  Not a Python package, so it comes straight from
  # the overlaid set rather than through `py` below — and pkgs/chemfiles-python
  # binds against exactly this derivation.
  #
  # There is deliberately no top-level alias for the *Python* binding, which is
  # also called `chemfiles`: one name cannot be both, and this is the split both
  # halves of the audience expect.  `pkgs.chemfiles` is the shared library, the
  # way every other distribution spells it; `python3Packages.chemfiles` is the
  # module, the way pip spells it.  See the callPackage site in
  # overlays/default.nix for how the two are kept from resolving to each other.
  inherit (pkgs') chemfiles;

  # enumlib, likewise not a Python package: the Fortran `enum.x` / `makestr.x`
  # that pymatgen's EnumlibAdaptor shells out to.  Top-level for the same reason
  # chemfiles is — it is an executable, not a module — and re-exported so that
  # ci.nix builds it and a consumer can put it on PATH beside a pymatgen that
  # needs it.  See pkgs/enumlib.
  inherit (pkgs') enumlib;

  # node-graph-widget-js, likewise not a Python package: the npm build whose
  # bundle pkgs/node-graph-widget copies in before hatchling runs.  It is a
  # top-level attribute of overlays.aiida and was simply never re-exported here,
  # so until now nothing built it in its own right.  See the binding in
  # overlays/default.nix and `preBuild` in pkgs/node-graph-widget.
  inherit (pkgs') node-graph-widget-js;

  # The two packages this repository defines that **cannot** be top-level
  # attributes, collected so that something still builds them.
  #
  # Everything else here is exposed at the top level, which is the rule: being
  # top-level is what makes ci.nix build a package in its own right, and a
  # package that nothing builds is a package nobody finds out is broken.  This
  # attribute used to hold seventy of them on the reasoning that a package with
  # exactly one dependant is built by that dependant anyway — which has a hole
  # in it, because a package reachable only through an `optional-dependencies`
  # entry has no such dependant, and `pkgs/sevenn` sat green-by-omission for
  # months that way.  The rule is now simply that everything is exposed, and
  # this attribute is what is left over.
  #
  # What is left over is exactly the name collisions.  Both of these are Python
  # bindings whose distribution name is already taken at the top level by a
  # *different* derivation, so promoting either would silently replace it —
  # here, and in any consumer of ./overlay.nix:
  #
  #   - `chemfiles`, where the top-level name is the C++ library.  See the
  #     `inherit (pkgs') chemfiles` note above, and the callPackage site in
  #     ./overlays/default.nix.
  #   - `trexio`, where the top-level name is *nixpkgs'* C library.  See the
  #     `trexio` binding in ./overlays/default.nix and the split in
  #     ./tests/chemtools/default.nix, which asserts this.
  #
  # Five packages are outside the rule for reasons that are not collisions and
  # are documented where they live: `tensorpotential` is unfree, and `just
  # ci-eval` forces drvPath over everything it can reach, so an unfree
  # derivation in any traversal is an evaluation error rather than a skipped
  # package (see ci.nix); `monty`, `pycifrw`, `qcelemental` and `qcengine` are
  # guarded backports, so on a new enough channel the attribute is nixpkgs' own
  # derivation and building it here would be CI populating a cache with packages
  # it does not own.  All five stay reachable as `python3Packages.<name>`.
  #
  # recurseIntoAttrs is the whole mechanism.  Both `nix-env -f . -qa '*'` (what
  # `just ci-eval` runs) and ci.nix's flattenPkgs descend into an attrset only
  # when it carries recurseForDerivations, which is exactly why python3Packages
  # above clears it — that one is the whole default set and descending would
  # mean all of nixpkgs.  This one is ours and bounded, so it takes the flag.
  #
  # **Reserved in overlay.nix and deliberately not in ci.nix**, which is the one
  # asymmetry between those two copies of the predicate.  Lifting an
  # `internalPackages` key into a consumer's nixpkgs would be as wrong as
  # lifting python3Packages; having ci.nix skip it would defeat the point of
  # the attribute.  Both files say so at their own predicate.
  internalPackages = pkgs'.lib.recurseIntoAttrs {
    inherit (py) chemfiles trexio;
  };

  # Python packages, reached through the extended python3Packages so that
  # these derivations are identical to what python3.withPackages returns.
  #
  # **Every Python package this repository defines is here**, the dependencies
  # carried for a single dependant included, because being a top-level attribute
  # is what makes ci.nix build a package in its own right.  The exceptions are
  # named at internalPackages above, and there are seven: two name collisions
  # that live there, and `tensorpotential`, `monty`, `pycifrw`, `qcelemental`
  # and `qcengine`, which are reachable as `python3Packages.<name>` for
  # reasons given at that note.
  #
  # Grouped by family, alphabetical within each group.
  inherit (py)
    # QCArchive
    parsl
    qcportal
    qcfractal
    qcfractalcompute
    qcarchivetesting

    # AiiDA
    aiida-ase
    aiida-core
    aiida-cp2k
    aiida-diff
    aiida-export-migration-tests
    aiida-firecrest
    aiida-gaussian
    aiida-gaussian-datatypes
    aiida-gromacs
    aiida-lammps
    aiida-nwchem
    aiida-octopus
    aiida-optimize
    aiida-orca
    aiida-phonopy
    aiida-pseudo
    aiida-psi4
    aiida-pythonjob
    aiida-quantumespresso
    aiida-restapi
    aiida-siesta
    aiida-submission-controller
    aiida-testing
    aiida-wannier90
    aiida-wannier90-workflows
    aiida-workgraph
    archive-path
    cp2k-input-tools
    cp2k-output-tools
    disk-objectstore
    firecrest-streamer
    graphene-file-upload
    kiwipy
    node-graph
    node-graph-widget
    pgsu
    pgtest
    postopus
    profilehooks
    pyfirecrest
    pytray
    qe-tools
    sisl
    starlette-graphene3
    upf-to-json

    # cheminformatics
    basis-set-exchange
    colour-science
    configurables
    dough
    griddataformats
    lwreg
    mda-xdrlib
    mdanalysis
    morfeus-ml
    mrcfile
    openprattle
    qmzyme
    xyzgraph

    # chemtools
    lwoniom
    molara
    pyrr
    sella
    strainjedi
    wignernj

    # materials
    ase-db-backends
    atomate2
    clusterscope
    cmcrameri
    custodian
    dargs
    deepmd-kit
    doped
    dpdata
    dpdata-plugin-test
    emmet-core
    fairchem-data-omat
    fairchem-data-omol
    fireworks
    hiphive
    jobflow
    jobflow-remote
    lobsterpy
    maggma
    maml
    matcalc
    matgl
    matminer
    matplotlib-label-lines
    mendeleev
    mongomock-ng
    mongomock-persistence
    mp-api
    mp-pyrho
    optimade
    p-tqdm
    parmed
    phono3py
    pubchempy
    pydefect
    pyfhiaims
    pymatgen
    pymatgen-analysis-alloys
    pymatgen-analysis-defects
    pymatgen-analysis-diffusion
    pymatgen-core
    pymatgen-io-aims
    pymatgen-io-validation
    qtoolkit
    quacc
    redun
    rootstock
    sevenn
    shakenbreak
    torch-pme
    trainstation
    vesin
    vise
    yellowbrick
    ;
}
# The three that are null rather than a derivation on a channel missing e3nn or
# warp-lang.  Filtered rather than passed through, so that nothing downstream of
# here — ./overlay.nix, ./ci.nix, a consumer — has to know that a top-level
# attribute might not be a package.  See the `fairchem-core` binding in
# ./overlays/default.nix.
// pkgs'.lib.filterAttrs (_: v: v != null) {
  inherit (py)
    fairchem-core
    fairchem-data-oc
    nvalchemi-toolkit-ops
    ;
}
