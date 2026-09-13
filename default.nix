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
  # way every other distribution spells it; `python313Packages.chemfiles` is the
  # module, the way pip spells it.  See the callPackage site in
  # overlays/default.nix for how the two are kept from resolving to each other.
  inherit (pkgs') chemfiles;

  # enumlib, likewise not a Python package: the Fortran `enum.x` / `makestr.x`
  # that pymatgen's EnumlibAdaptor shells out to.  Top-level for the same reason
  # chemfiles is — it is an executable, not a module — and re-exported so that
  # ci.nix builds it and a consumer can put it on PATH beside a pymatgen that
  # needs it.  See pkgs/enumlib.
  inherit (pkgs') enumlib;

  # The packages this repository defines and deliberately does *not* re-export
  # at the top level, collected so that something builds them.
  #
  # Sixty-odd of the packages here are dependencies of one dependant each —
  # kiwipy, plumpy, mdanalysis, clusterscope and the rest — and stay internal on
  # purpose: being top-level is what makes ci.nix build a package in its own
  # right, and a package with exactly one dependant is built by that dependant
  # anyway.  That reasoning has a hole in it, and this attribute is the patch.
  # A package reachable *only* through an `optional-dependencies` entry has no
  # such dependant: an extra is not a build input of the package that declares
  # it, so nothing builds sevenn, deepmd-kit, dpdata, maml, rootstock or
  # nvalchemi-toolkit-ops at all.  `pkgs/sevenn` sat green-by-omission for
  # months that way and failed the first time anyone built it.
  #
  # recurseIntoAttrs is the whole mechanism.  Both `nix-env -f . -qa '*'` (what
  # `just ci-eval` runs) and ci.nix's flattenPkgs descend into an attrset only
  # when it carries recurseForDerivations, which is exactly why python313Packages
  # above clears it — that one is the whole 3.13 set and descending would mean
  # all of nixpkgs.  This one is ours and bounded, so it takes the flag.
  #
  # **Reserved in overlay.nix and deliberately not in ci.nix**, which is the one
  # asymmetry between those two copies of the predicate.  Lifting an
  # `internalPackages` key into a consumer's nixpkgs would be as wrong as
  # lifting python313Packages; having ci.nix skip it would defeat the point of
  # the attribute.  Both files say so at their own predicate.
  #
  # Three kinds of package are kept out, each for a reason that would otherwise
  # cost more than it buys:
  #
  #   - `tensorpotential`, because it is unfree.  `just ci-eval` walks this
  #     attrset forcing drvPath, and an unfree derivation there is an evaluation
  #     error rather than a skipped package — see the note in ci.nix.  Keeping
  #     it out of every traversal is the same arrangement that keeps it out of
  #     the top level.
  #   - `monty` and `pycifrw`, which are guarded backports rather than packages
  #     of ours: on a channel that is new enough they are nixpkgs' own
  #     derivations, and building those here would be CI populating a cache with
  #     packages it does not own.  pymatgen-core and aiida-core build them where
  #     they are ours.
  #   - `graphrc` and `node-graph-widget-js`, which are top-level attributes of
  #     their overlays rather than members of a Python set — graphrc because
  #     cclib forces it to be, and so it is `meta.broken` on this path anyway.
  #
  # A null member is filtered rather than passed through: `fairchem-core`,
  # `fairchem-data-oc` and `nvalchemi-toolkit-ops` are null on channels missing
  # e3nn or warp-lang, and nothing downstream of here should have to know that.
  internalPackages = pkgs'.lib.recurseIntoAttrs (
    pkgs'.lib.filterAttrs (_: v: v != null) {
      # The Python chemfiles binding.  Spelled out rather than inherited
      # because the name is taken at the top level by the C++ library, which is
      # a different derivation — see the `inherit (pkgs') chemfiles` note above.
      inherit (py) chemfiles;

      inherit (py)
        # cheminformatics
        basis-set-exchange
        colour-science
        configurables
        griddataformats
        lwreg
        mda-xdrlib
        mdanalysis
        mrcfile
        openprattle
        xyzgraph

        # chemtools
        lwoniom
        pyrr
        trexio

        # materials
        ase-db-backends
        clusterscope
        cmcrameri
        dargs
        deepmd-kit
        doped
        dpdata
        dpdata-plugin-test
        fairchem-core
        fairchem-data-oc
        fairchem-data-omat
        fairchem-data-omol
        hiphive
        maml
        matplotlib-label-lines
        mendeleev
        mongomock-ng
        mongomock-persistence
        mp-pyrho
        nvalchemi-toolkit-ops
        p-tqdm
        parmed
        pydefect
        pyfhiaims
        pymatgen-io-aims
        rootstock
        sevenn
        torch-pme
        trainstation
        vesin
        yellowbrick

        # aiida
        aiida-diff
        aiida-export-migration-tests
        aiida-gaussian-datatypes
        aiida-optimize
        aiida-pseudo
        aiida-testing
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
        plumpy
        postopus
        profilehooks
        pyfirecrest
        pytray
        qe-tools
        sisl
        starlette-graphene3
        upf-to-json
        ;
    }
  );

  # Python packages, reached through the extended python313Packages so that
  # these derivations are identical to what python313.withPackages returns.
  inherit (py)
    parsl
    qcportal
    qcfractal
    qcfractalcompute
    qcarchivetesting

    aiida-core
    aiida-ase
    aiida-cp2k
    aiida-gaussian
    aiida-gromacs
    aiida-lammps
    aiida-nwchem
    aiida-octopus
    aiida-orca
    aiida-psi4
    aiida-quantumespresso
    aiida-firecrest
    aiida-phonopy
    aiida-pythonjob
    aiida-restapi
    aiida-shell
    aiida-siesta
    aiida-submission-controller
    aiida-wannier90
    aiida-wannier90-workflows
    aiida-workgraph

    morfeus-ml
    qmzyme
    dough

    wignernj
    strainjedi
    sella
    molara

    atomate2
    custodian
    emmet-core
    fireworks
    jobflow
    jobflow-remote
    lobsterpy
    maggma
    matcalc
    matgl
    matminer
    mp-api
    optimade
    phono3py
    pubchempy
    pymatgen
    pymatgen-analysis-alloys
    pymatgen-analysis-defects
    pymatgen-analysis-diffusion
    pymatgen-core
    pymatgen-io-validation
    qtoolkit
    quacc
    redun
    shakenbreak
    vise
    ;
}
