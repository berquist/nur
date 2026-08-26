# overlays/default.nix
#
# Exposed as the `overlays` reserved key in default.nix and re-exported
# by flake.nix as `self.overlays`.
#
# Each value is a standard  final: prev: { ... }  overlay function.
# Add new overlays here as additional attributes; default.nix composes
# them all via lib.composeManyExtensions.
let
  # nixpkgs carries `disabled = pythonAtLeast "3.13"` on pymatgen, so
  # `pkgs.python313Packages.pymatgen` throws at evaluation rather than merely
  # failing to build.  That gate is upstream nixpkgs being conservative about an
  # interpreter it has not tested, not pymatgen refusing to run: lifting it
  # instantiates and its whole closure evaluates on 3.13 unchanged.
  #
  # It cannot simply be dropped instead.  aiida-quantumespresso depends on
  # `aiida_core[atomic_tools]`, pymatgen is in that extra, and the alternative —
  # pinning that whole family to 3.12 — would put a third interpreter in the
  # repo for the sake of one nixpkgs annotation.  The materials overlay needs
  # the same lift for a different reason: custodian's suite imports pymatgen in
  # seven of its twenty-one modules.
  #
  # **A function returning a `let`-bindable value, never a member of a package
  # set.**  Injecting a repaired pymatgen into the set would silently change
  # pymatgen for everything else in a consumer's package set, which taking
  # `overlays.aiida` or `overlays.materials` has no business doing.  Each
  # caller binds it locally and passes it to the packages that need it — for
  # aiida that is aiida-core and aiida-gaussian, for materials it is custodian.
  # The aiida-overlay-pymatgen-override-is-local eval test asserts it stays
  # invisible from outside.
  #
  # Shared rather than copied because the nine deselections and the plotting
  # patch below are the expensive part to keep in step, and two overlays
  # drifting apart on which pymatgen tests fail would be invisible until one of
  # them broke.
  #
  # Those nine are none of them ours and none of them about the interpreter.
  # They are pymatgen 2025.10.7 against dependency versions newer than it was
  # released for, in three groups:
  #
  #   pandas 3.0 removed DataFrame.swapaxes, which is what made
  #   `np.array_split` return DataFrames rather than plain arrays.  The
  #   LammpsData writers slice the result with `.iloc` immediately afterwards.
  #
  #   The thermal-displacement eigenvectors come back complex, and `np.degrees`
  #   refuses a complex argument.  Upstream assumes a real result from the
  #   diagonalisation.
  #
  #   The Heisenberg mapper's least-squares fit does not converge here, so
  #   `ex_params` stays None and both tests that read it fail.  nixpkgs already
  #   deselects `test_mean_field` on aarch64-linux for this exact error; the fit
  #   is evidently sensitive to which BLAS it finds, and x86_64 with our overlay
  #   is another such combination.
  #
  #   `pmg view` opens a viewer and takes the xdist worker down with it when
  #   there is no display.  nixpkgs deselects the neighbouring
  #   tests/cli/test_pmg_plot.py on darwin for the same reason.
  #
  # Node ids rather than bare names: `disabledTests` becomes a `-k` expression,
  # and `test_get_str` and `test_write_file` are common enough in a suite this
  # size to take unrelated tests with them.  An entry containing `::` is passed
  # to pytest as `--deselect`, which is exact.
  pymatgenFor =
    pself:
    pself.pymatgen.overridePythonAttrs (old: {
      disabled = false;
      disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
        "tests/io/lammps/test_data.py::TestLammpsData::test_get_str"
        "tests/io/lammps/test_data.py::TestLammpsData::test_write_file"
        "tests/io/lammps/test_data.py::TestCombinedData::test_get_str"
        "tests/io/lammps/test_data.py::TestCombinedData::test_as_lammpsdata"
        "tests/phonon/test_thermal_displacements.py::TestThermalDisplacement::test_compute_directionality_quality_criterion"
        "tests/phonon/test_thermal_displacements.py::TestThermalDisplacement::test_visualization_directionality_criterion"
        "tests/analysis/magnetism/test_heisenberg.py::TestHeisenbergMapper::test_mean_field"
        "tests/analysis/magnetism/test_heisenberg.py::TestHeisenbergMapper::test_get_igraph"
        "tests/cli/test_pmg.py::test_pmg_view"
      ];

      # A tenth failure that is not a deselect, because it is a flake
      # rather than a broken test, and deselecting it would drop real
      # coverage of van_arkel_triangle:
      #
      #   assert ax.get_title() == ""
      #   E  AssertionError: assert 'Coordination numbers' == ''
      #
      # van_arkel_triangle sets no title.  It ends with `ax = plt.gca()`
      # — pyplot's *current* axes, whatever that happens to be — and
      # tests/analysis/chemenv/coordination_environments/test_structure_environments.py
      # calls get_environments_figure, whose title defaults to
      # "Coordination numbers", and never closes the figure.  When both
      # land in one xdist worker in that order the assertion reads the
      # leftover.  Which tests share a worker is a scheduling accident
      # under xdist's default --dist load, so this appears and vanishes
      # between runs; --numprocesses is $NIX_BUILD_CORES, and 128 workers
      # make it likely enough to matter here and rare enough that nixpkgs
      # has never had to deselect it.
      #
      # Retrying would not help, and pytest-rerunfailures is deliberately
      # not the answer as it is for aiida-core: a rerun runs in the same
      # process and finds the same stale figure.
      #
      # So give the test the clean state it assumes.  `plt` is already
      # imported at the top of that file, and the second van_arkel_triangle
      # call in the test only asserts isinstance, so nothing else moves.
      postPatch = (old.postPatch or "") + ''
        substituteInPlace tests/util/test_plotting.py \
          --replace-fail \
            '        random_list = [("Fe", "C"), ("Ni", "F")]' \
            '        plt.close("all")
                random_list = [("Fe", "C"), ("Ni", "F")]'
      '';
    });
in
{
  # dotdrop is a standalone CLI application — nothing here imports it as a
  # library — so it is a plain top-level package rather than a
  # pythonPackagesExtensions entry, and it follows the default `python3`
  # instead of the 3.13 pin the QCArchive set is stuck on.  Keeping it in its
  # own overlay is what lets a consumer take `overlays.dotdrop` without
  # dragging in qcportal and its closure.
  dotdrop = final: _prev: {
    dotdrop = final.python3Packages.callPackage ../pkgs/dotdrop { };
  };

  # harmonwig is a standalone CLI like dotdrop — nothing here imports it as a
  # library — so it is a plain top-level package following the default python3.
  #
  # Its cclib dependency comes from upstream cclib's own flake, which this file
  # cannot reach.  callPackage leaves the derivation's defaulted `cclib`
  # argument alone when the package set has no cclib, and the derivation carries
  # meta.broken in that case, so this overlay evaluates everywhere and only
  # produces a buildable harmonwig when composed *after* cclib's overlay.
  # ../flake.nix does that composition; see cclibPkgs there.
  #
  # `final.python3.pkgs`, NOT `final.python3Packages`.  The two are ordinarily
  # interchangeable and are not here: nixpkgs defines
  # `python3Packages = dontRecurseIntoAttrs python314Packages`, an alias to the
  # *versioned* set, while cclib's overlay overrides the `python3` attribute.
  # So `python3Packages` never sees cclib, `callPackage` silently leaves the
  # defaulted argument at null, and the result is a harmonwig that is
  # meta.broken even on the flake path — with nothing to say so.
  harmonwig = final: _prev: {
    harmonwig = final.python3.pkgs.callPackage ../pkgs/harmonwig { };
  };

  # Standalone computational chemistry and cheminformatics libraries and CLIs:
  # DBSTEP, morfeus, aqme, QMzyme, ccreg, digichem — plus the dozen-odd
  # dependencies of those that nixpkgs does not carry.  Unrelated to both
  # QCArchive and AiiDA, and kept in its own overlay for the same reason those
  # two are kept apart: a consumer can take one family without the other's
  # closure.
  #
  # Everything that does *not* need cclib lives here.  The four packages that
  # do are in cheminformatics-cclib below, for the reason spelled out there.
  cheminformatics = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pself: psuper: {
        # A repair of a nixpkgs package, not one of ours, in the same spirit as
        # aiormq and aio-pika in the aiida overlay below — and in the package
        # set rather than in a `let` binding for the same reason: nothing here
        # constructs rdkit, so its dependants can only pick the fix up through
        # pself.
        #
        # nixpkgs builds rdkit with CMake and `pyproject = false`, so what lands
        # in site-packages is a bare `rdkit/` tree with no `.dist-info` beside
        # it.  The package imports perfectly; it is simply invisible to
        # `importlib.metadata`, which is what pythonRuntimeDepsCheckHook uses to
        # resolve a wheel's Requires-Dist.  So every dependant that declares
        # rdkit in its own metadata fails the check with
        #
        #     Checking runtime dependencies for qmzyme-…-py3-none-any.whl
        #       - rdkit not installed
        #
        # while rdkit sits in the closure, importable.  qmzyme is the one that
        # bites today; aqme and digichem-core declare it too and are latent.
        # ../pkgs/ccreg only escapes because upstream hides rdkit in
        # `[tool.pixi.dependencies]`, where the wheel metadata never sees it.
        #
        # METADATA alone is enough, and is all this writes: the hook goes
        # through `importlib.metadata.distribution()`, which needs a
        # `<name>-<version>.dist-info` directory with a Name and a Version and
        # reads nothing else.  A RECORD would have to list real hashes to be
        # worth anything, and nothing here would read it.
        #
        # Note the cost: this rebuilds rdkit from source rather than
        # substituting it, and rdkit is a large C++ build.  The cheap
        # alternative is `pythonRemoveDeps = [ "rdkit" ]` on each dependant,
        # which keeps the cached rdkit and drops the declaration instead — see
        # ../pkgs/ccreg/default.nix for that shape.  Fixing rdkit once was
        # judged the better trade because the failure is upstream's and every
        # dependant would otherwise carry the same workaround.  Drop this when
        # nixpkgs installs rdkit as a wheel.
        rdkit = psuper.rdkit.overridePythonAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            distInfo="$out/${pself.python.sitePackages}/rdkit-${old.version}.dist-info"
            mkdir -p "$distInfo"
            printf 'Metadata-Version: 2.1\nName: rdkit\nVersion: %s\n' \
              "${old.version}" >"$distInfo/METADATA"
          '';
        });

        # Dependencies missing from nixpkgs.  Not re-exported at the top level
        # or from ../default.nix: they are implementation detail, and every
        # top-level attribute is another thing ci.nix builds.
        basis-set-exchange = pself.callPackage ../pkgs/basis-set-exchange { };
        colour-science = pself.callPackage ../pkgs/colour-science { };
        configurables = pself.callPackage ../pkgs/configurables { };
        griddataformats = pself.callPackage ../pkgs/griddataformats { };
        lwreg = pself.callPackage ../pkgs/lwreg { };
        mda-xdrlib = pself.callPackage ../pkgs/mda-xdrlib { };
        mdanalysis = pself.callPackage ../pkgs/mdanalysis { };
        mrcfile = pself.callPackage ../pkgs/mrcfile { };
        openprattle = pself.callPackage ../pkgs/openprattle { };

        morfeus-ml = pself.callPackage ../pkgs/morfeus-ml { };
        qmzyme = pself.callPackage ../pkgs/qmzyme { };

        # dough parses simulation-code output files into typed dataclasses.  It
        # belongs with cclib and openprattle above rather than with the
        # materials overlay: its ase/pymatgen/aiida-core converters are optional
        # extras imported lazily, so nothing of those closures is pulled in.
        dough = pself.callPackage ../pkgs/dough { };

        # xyzgraph is here rather than in cheminformatics-cclib below because it
        # is the one link in that chain that does *not* need cclib — it wants
        # rdkit and networkx only.  That matters structurally: because this
        # extension is injected into every pythonX.pkgs set, `final.python3.pkgs`
        # gets an xyzgraph too, which is what lets ../pkgs/graphrc and
        # ../pkgs/xyzrender resolve it from the one set that does have cclib.
        #
        # A dependency of those two, so it stops at this line and is not
        # re-exported.
        xyzgraph = pself.callPackage ../pkgs/xyzgraph { };
      })
    ];

    # Top-level aliases for the two public packages, on the same python313 pin
    # the rest of this repo uses.  Keep in sync with the `inherit (py)` list in
    # ../default.nix.
    #
    # qmzyme is reachable here rather than in cheminformatics-cclib because its
    # cclib use is test-only and lazy — see ../pkgs/qmzyme/default.nix.  It
    # builds on both paths; the flake path additionally runs one more test.
    inherit (final.python313Packages)
      dough
      morfeus-ml
      qmzyme
      ;
  };

  # The four packages above that cannot be built without cclib.
  #
  # These are top-level `python3.pkgs.callPackage` calls rather than
  # pythonPackagesExtensions entries, exactly like harmonwig above, and for the
  # same reason: cclib's overlay overrides the top-level `python3` and nothing
  # else, so `final.python3.pkgs` is the only package set in which cclib
  # exists.  `final.python313Packages` — which every other family here uses —
  # is a *different* set that cclib's overlay never touches, so aliasing these
  # from there would silently yield the broken build.  See harmonwig above for
  # why it must not be spelled `final.python3Packages` either.
  #
  # Nothing in this repo imports any of them as a library, so none of them
  # needs to be in a Python package set at all.  Their own non-cclib
  # dependencies (morfeus-ml, colour-science, lwreg, …) come from
  # cheminformatics above, which does inject into every interpreter.
  cheminformatics-cclib = final: _prev: {
    # xtb and crest are threaded in by hand because no single spelling resolves
    # on both package sets this overlay is applied to.  Both are `qchem.*` from
    # NixOS-QChem's overlay on the set ../flake.nix builds aqme against; xtb is
    # additionally a top-level attribute of nixpkgs-unstable, and crest is not
    # in nixpkgs at all.  The `or null` tail is what keeps the attribute-path
    # lookup from throwing on a set that has neither, and aqme then skips just
    # the test files that need the missing program.
    aqme = final.python3.pkgs.callPackage ../pkgs/aqme {
      xtb = final.xtb or final.qchem.xtb or null;
      crest = final.crest or final.qchem.crest or null;
    };
    ccreg = final.python3.pkgs.callPackage ../pkgs/ccreg { };
    dbstep = final.python3.pkgs.callPackage ../pkgs/dbstep { };
    digichem-core = final.python3.pkgs.callPackage ../pkgs/digichem-core { };
    metallogen = final.python3.pkgs.callPackage ../pkgs/metallogen { };
    molcat = final.python3.pkgs.callPackage ../pkgs/molcat { };
    xyzrender = final.python3.pkgs.callPackage ../pkgs/xyzrender { };

    # graphrc breaks the rule this file otherwise keeps, and it has to.
    #
    # Nothing but xyzrender wants it, so by the convention in ../AGENTS.md it
    # should stop at a `pythonPackagesExtensions` entry and never become a
    # top-level attribute.  But it needs cclib, and `final.python313Packages` —
    # the set that extension feeds — is precisely the set cclib's overlay never
    # touches.  So it must be a top-level `final.python3.pkgs.callPackage` like
    # its neighbours here, while still not being re-exported from
    # ../default.nix, so ci.nix does not build it in its own right.
    #
    # ../tests/cheminformatics asserts that exact shape, because it is the only
    # thing keeping the two halves of it from drifting.
    graphrc = final.python3.pkgs.callPackage ../pkgs/graphrc { };
  };

  # Standalone computational chemistry tools that share no closure with each
  # other and none with the families above: angular-momentum coefficients, a
  # strain-analysis CLI, a terminal structure viewer, a saddle-point optimizer,
  # and the chemfiles trajectory library with its Python binding.
  #
  # A single overlay rather than five, because the alternative is five overlay
  # attributes whose only content is one callPackage each.  Nothing here is
  # heavy to *evaluate* — a consumer taking this overlay pays for nothing it
  # does not build — so the usual reason to split on closure boundaries does not
  # apply.  Note that molara does drag PySide6 and sella drags jax, so both are
  # real costs once ci.nix starts building them.
  chemtools = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pself: _psuper: {
        wignernj = pself.callPackage ../pkgs/wignernj { };
        strainjedi = pself.callPackage ../pkgs/strainjedi { };
        sella = pself.callPackage ../pkgs/sella { };
        molara = pself.callPackage ../pkgs/molara { };

        # Carried for molara alone, because nixpkgs *removed* pyrr rather than
        # merely lacking it — so unlike the other dependencies here there is no
        # attribute to fall back to, and `python-aliases.nix` throws on the
        # name.  Not re-exported; see the header of ../pkgs/pyrr for when to
        # delete this.
        pyrr = pself.callPackage ../pkgs/pyrr { };

        # The Python binding, for moltui's `trexio` extra.  Emphatically **not**
        # re-exported to the top level, and this is the one case in this file
        # where that would do real damage rather than merely being untidy:
        # nixpkgs already has a top-level `trexio`, and it is the C library.
        # Lifting this over it would replace a C library with a Python module
        # for every consumer of the overlay, and the two are not substitutes.
        #
        # The reverse of ../pkgs/chemfiles-python's problem, and it needs no
        # `chemfilesLib`-style rename because this derivation takes no `trexio`
        # argument — it builds the C sources itself out of the sdist.
        trexio = pself.callPackage ../pkgs/trexio { };

        # The C++ library is threaded in from `final` by hand.  It has to be:
        # this attribute is also called `chemfiles`, and a python-set callPackage
        # resolves the Python attribute before falling back to the top level, so
        # a defaulted `chemfiles` argument in the derivation would bind to this
        # very package and recurse.  Naming the argument `chemfilesLib` and
        # passing it explicitly is what breaks the cycle — the same shape as
        # aiida-core's `jq` and postopus's `octopus`.
        chemfiles = pself.callPackage ../pkgs/chemfiles-python {
          chemfilesLib = final.chemfiles;
        };
      })
    ];

    # The C++ library itself is not a Python package and so is a plain
    # top-level callPackage, not a member of the extension above.
    chemfiles = final.callPackage ../pkgs/chemfiles { };

    # moltui is a standalone TUI application — nothing here imports it as a
    # library — so it is a `buildPythonApplication`, and that is precisely why
    # it cannot go in the extension above: a buildPythonApplication is not a
    # Python module, and nixpkgs rejects one that turns up in a package set with
    #
    #   error: moltui should use `buildPythonPackage` or `toPythonModule` if it
    #   is to be part of the Python packages set.
    #
    # Same arrangement as dotdrop and harmonwig at the top of this file,
    # including following the default `python3` rather than the 3.13 pin.
    moltui = final.python3Packages.callPackage ../pkgs/moltui { };

    # Keep in sync with the `inherit (py)` list in ../default.nix.
    inherit (final.python313Packages)
      wignernj
      strainjedi
      sella
      molara
      ;
  };

  # The materials-project workflow family.  Only custodian and fireworks today,
  # which between them need nothing nixpkgs lacks — but they are the two leaves
  # of a much larger tree (jobflow, atomate2, quacc, matgl, …) that is gated on
  # six missing shared dependencies: pymatgen-core, emmet-core, maggma,
  # mp-pyrho, qtoolkit and mp-api.  This overlay exists now so that work has an
  # obvious home when those land, rather than being wedged into cheminformatics.
  materials = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (
        pself: _psuper:
        let
          # custodian's suite imports pymatgen in seven of its twenty-one
          # modules, and nixpkgs gates pymatgen off 3.13.  Same lift the aiida
          # overlay needs; see `pymatgenFor` at the top of this file, including
          # why it stays a `let` binding rather than entering the package set.
          pymatgen = pymatgenFor pself;
        in
        {
          custodian = pself.callPackage ../pkgs/custodian { inherit pymatgen; };
          fireworks = pself.callPackage ../pkgs/fireworks { };

          # A test-only dependency of fireworks, so it stops here rather than
          # being re-exported: it stays reachable as python313Packages.* without
          # ci.nix building it in its own right.
          mongomock-persistence = pself.callPackage ../pkgs/mongomock-persistence { };
        }
      )
    ];

    # Keep in sync with the `inherit (py)` list in ../default.nix.
    inherit (final.python313Packages)
      custodian
      fireworks
      ;
  };

  # The AiiDA ecosystem: aiida-core, the six quantum chemistry plugins, and
  # the dependencies of both that nixpkgs does not carry.  Injected through
  # pythonPackagesExtensions for the same reason the qcfractal overlay is —
  # plugins are found through entry points, so a plugin and the aiida-core it
  # extends must come from one package set, and pself gives that for free.
  #
  # Kept separate from qcfractal so that a consumer can take overlays.aiida
  # without dragging in qcportal's closure, and vice versa.  The two share
  # nothing but the interpreter.
  aiida = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (
        pself: psuper:
        let
          # The interpreter gate lifted and nine unrelated tests deselected.
          # Shared with the materials overlay below rather than spelled out
          # twice; the whole explanation lives at `pymatgenFor` at the top of
          # this file, including why it must stay a `let` binding and never
          # become a member of the attrset below.
          #
          # Passed explicitly to the two packages that need it: aiida-core, and
          # aiida-gaussian, which depends on pymatgen directly.
          pymatgen = pymatgenFor pself;

          # nixpkgs' pythonMetadataCheckPhase — which compares a built wheel's
          # METADATA against the `version` its derivation declares — and the
          # pyprojectVersionPatchHook that answers it arrived together, after
          # 26.05.  On a channel carrying neither, the two mosquito overrides
          # below are impossible *and* unnecessary: naming a hook that is not an
          # attribute aborts evaluation of everything downstream of it, and
          # nothing is comparing the two versions in the first place.  Both
          # packages then install under the version their pyproject.toml really
          # carries — aiormq 6.9.2, aio-pika 9.6.0 — which is what their
          # dependants ask for anyway, so the unpatched derivations are the ones
          # that work there.
          #
          # Keyed on the hook rather than on lib.version, because the hook is
          # the attribute that would throw, and a backport to a stable channel
          # would bring both halves of the change at once.
          hasMetadataCheck = pself ? pyprojectVersionPatchHook;
        in
        {
          # Two nixpkgs packages, neither of them ours, that the AiiDA closure
          # cannot be built without.  Both are `mosquito` projects and both
          # carry the same upstream slip: the release was tagged without
          # bumping the version in pyproject.toml, so the built wheel's METADATA
          # disagrees with what nixpkgs declares and pythonMetadataCheckPhase
          # refuses it.  pyprojectVersionPatchHook rewrites the project file to
          # match `version`, which is what nixpkgs' own error message
          # recommends.
          #
          # Both overrides have to live in the package set rather than in a
          # `let` binding, unlike pymatgen above: the broken derivations are
          # below us in the graph and nothing here constructs them, so aio-pika
          # and kiwipy can only pick the fixes up through pself.  Overriding
          # them for a consumer of overlays.aiida is a repair rather than a
          # surprise — without it neither attribute builds at all.
          #
          # Both are guarded on `hasMetadataCheck` above, which is what keeps
          # them off the 26.05 leg of the matrix.
          #
          # Remove both once nixpkgs carries the fixes; for aiormq see
          # ../.scratch/nixpkgs-aiormq-fix.patch.

          # aiormq is the worse of the two, because it has never released a
          # 9.6.4 at all: upstream pushed 6.9.4 and 9.6.4 on the same day,
          # pointing at the same commit, and nixpkgs picked up the
          # transposed-digit duplicate.  Two things then go wrong, and both have
          # to be fixed together — fixing either alone still fails:
          #
          #   1. That commit's pyproject.toml still says 6.9.2, so
          #      pythonMetadataCheckPhase rejects the mismatch outright.
          #      pyprojectVersionPatchHook rewrites it to `version`.
          #   2. aio-pika requires `aiormq<7,>=6.8`, which 9.6.4 does not
          #      satisfy.  So `version` has to become 6.9.4 as well — patching
          #      the metadata to say 9.6.4 merely moves the failure downstream.
          #
          # src is deliberately left alone.  It still fetches the 9.6.4 tag,
          # which is the same tree as 6.9.4 — identical NAR hash — so there is
          # nothing to gain from re-pointing it and a hash to get wrong.
          aiormq =
            if hasMetadataCheck then
              psuper.aiormq.overridePythonAttrs (old: {
                version = "6.9.4";
                build-system = (old.build-system or [ ]) ++ [ pself.pyprojectVersionPatchHook ];
              })
            else
              psuper.aiormq;

          # aio-pika is the ordinary case of the same slip: nixpkgs declares
          # 9.6.2 and fetches that tag, but the tree there still says 9.6.0.
          # No version change, unlike aiormq above — 9.6.2 is a real release in
          # the right series, and kiwipy's `aio-pika~=9.4` accepts it — so the
          # hook alone is the whole fix.
          aio-pika =
            if hasMetadataCheck then
              psuper.aio-pika.overridePythonAttrs (old: {
                build-system = (old.build-system or [ ]) ++ [ pself.pyprojectVersionPatchHook ];
              })
            else
              psuper.aio-pika;

          # monty is a third nixpkgs package that does not build, reached here
          # through pymatgen, and its failure is a real bug rather than a test
          # artefact.  MontyEncoder recognises pandas objects by walking the MRO
          # and comparing `f"{cls.__module__}.{cls.__qualname__}"` against a
          # literal — `_check_type` says as much in its docstring.  pandas 3.0
          # decorates DataFrame and Series with `@set_module("pandas")`, so that
          # string is now "pandas.DataFrame", not "pandas.core.frame.DataFrame",
          # and the branch is simply never taken.
          #
          # An earlier revision of this file skipped monty's two `test_pandas`
          # tests on the claim that nothing in the AiiDA closure uses the pandas
          # path.  That was wrong: pymatgen's LammpsData.as_dict serialises
          # DataFrames through MontyEncoder, and four of its tests failed with
          # "Object of type DataFrame is not JSON serializable" as soon as monty
          # built.  Skipping a test that is reporting a defect only moves the
          # failure downstream.
          #
          # Both spellings are accepted rather than replacing one with the
          # other, so the override stays correct against pandas 2 as well.  The
          # `jsanitize` path needs nothing: it already matches on
          # pandas.core.base.PandasObject, a base class that keeps its real
          # module, and _check_type walks the whole MRO.
          #
          # test_json.py's TestCheckType::test_pandas asserts a spelling
          # directly, so it gets the same tuple rather than the new spelling
          # alone.  Rewriting it to "pandas.DataFrame" was a pandas 3
          # assumption, and it failed the other way round on the nixos-26.05 leg
          # of the matrix, which carries pandas 2.3.3:
          #
          #     assert _check_type(df, "pandas.DataFrame")
          #     E  AssertionError: assert False
          #
          # With the tuple the assertion is true under either pandas, and it
          # tests what the library actually calls rather than one spelling of
          # it.
          #
          # Only for monty older than 2026.7.16.  That release restructured
          # json.py into TypeHandler classes and fixed this upstream in the
          # same way — PandasHandler carries `_DF_QUALNAMES` and
          # `_SERIES_QUALNAMES`, both of them the two-spelling tuples above —
          # so the literals these replacements look for no longer exist and
          # every --replace-fail aborts the build.  Both unstable legs of the
          # matrix carry 2026.7.16; nixos-26.05 carries 2025.3.3 and still
          # needs the patch.  Delete the whole binding once 26.05 leaves
          # ../Justfile's `channels`.
          #
          # Keyed on the version rather than on some attribute that would
          # throw, unlike hasMetadataCheck above: nothing about the derivation
          # says which shape the source has, and the source itself is not
          # readable at evaluation time.
          monty =
            if final.lib.versionOlder psuper.monty.version "2026.7.16" then
              psuper.monty.overridePythonAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace src/monty/json.py \
                    --replace-fail '_check_type(o, "pandas.core.frame.DataFrame")' \
                                   '_check_type(o, ("pandas.core.frame.DataFrame", "pandas.DataFrame"))' \
                    --replace-fail '_check_type(o, "pandas.core.series.Series")' \
                                   '_check_type(o, ("pandas.core.series.Series", "pandas.Series"))'

                  substituteInPlace tests/test_json.py \
                    --replace-fail 'assert _check_type(df, "pandas.core.frame.DataFrame")' \
                                   'assert _check_type(df, ("pandas.core.frame.DataFrame", "pandas.DataFrame"))' \
                    --replace-fail 'assert _check_type(series, "pandas.core.series.Series")' \
                                   'assert _check_type(series, ("pandas.core.series.Series", "pandas.Series"))'
                '';
              })
            else
              # 2026.7.16 fixed the pandas bug above and introduced this one in
              # the same rewrite, so the new branch is not "no patch needed".
              #
              # monty imports bson at module scope and leaves it None when
              # pymongo is absent.  The rewrite moved decoding into handler
              # classes registered in `_DECODER_HANDLERS` at import time — bson
              # among them, registered whether or not the import succeeded — and
              # guarded the dispatch site with `except ImportError`, whose own
              # comment says it is there to "fall through to the generic
              # resolver / raw dict" when an optional dependency is missing.
              # BsonHandler.matches checks `bson is None`; BsonHandler.decode
              # does not, so it dereferences None, raises AttributeError, and
              # sails past that except clause.  Before the rewrite the whole
              # bson branch sat behind `if bson is not None` and an ObjectId
              # document decoded to a plain dict.
              #
              # Raising ImportError is what makes the existing handler do what
              # its comment already claims.  It goes before the `@class` test so
              # DBRef is covered too, not just ObjectId.
              #
              # This is invisible from monty's own suite, which is why upstream
              # has it: nixpkgs hands monty its whole `optional` extra as
              # nativeCheckInputs, and that pulls in pymongo, so `bson` is never
              # None there.  pymatgen declares no pymongo — upstream pymatgen
              # does not either — and its tests/io/vasp/test_sets.py fixture
              # holds a serialised ObjectId, so test_grid_size_from_struct is
              # where the defect actually surfaces.
              psuper.monty.overridePythonAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace src/monty/json.py \
                    --replace-fail \
                      '        if d["@class"] == "ObjectId":' \
                      '        if bson is None:
                              raise ImportError("bson is not installed")
                          if d["@class"] == "ObjectId":'
                '';
              });

          # Dependencies missing from nixpkgs.  Not re-exported at the top level
          # or from ../default.nix: they are implementation detail, and every
          # top-level attribute is another thing ci.nix builds.
          archive-path = pself.callPackage ../pkgs/archive-path { };
          disk-objectstore = pself.callPackage ../pkgs/disk-objectstore { };
          pgsu = pself.callPackage ../pkgs/pgsu { };
          pytray = pself.callPackage ../pkgs/pytray { };
          kiwipy = pself.callPackage ../pkgs/kiwipy { };
          plumpy = pself.callPackage ../pkgs/plumpy { };
          upf-to-json = pself.callPackage ../pkgs/upf-to-json { };
          pgtest = pself.callPackage ../pkgs/pgtest { };

          # Missing from nixos-26.05 and present from 26.11, so this one is a
          # backport rather than a package of ours: take the channel's whenever
          # it has one, and fall back for the leg that does not.  `psuper`, not
          # `pself`, or the fallback would refer to itself.  See ../pkgs/pycifrw
          # for what it unblocks and when to delete it.
          pycifrw = psuper.pycifrw or (pself.callPackage ../pkgs/pycifrw { });

          # Here for one reason only: disk-objectstore ships
          # disk_objectstore/examples/example_objectstore.py, which imports it at
          # module scope, and nixpkgs does not carry it.
          profilehooks = pself.callPackage ../pkgs/profilehooks { };

          # Plugin dependencies, likewise missing from nixpkgs and likewise not
          # re-exported.  aiida-testing is test-only — it is what supplies
          # aiida-psi4's mock_code fixture — but it lives here rather than in a
          # checkInputs-only position because pself is the only thing that can
          # resolve its own aiida-core to the same derivation.
          qe-tools = pself.callPackage ../pkgs/qe-tools { };
          aiida-pseudo = pself.callPackage ../pkgs/aiida-pseudo { };
          aiida-gaussian-datatypes = pself.callPackage ../pkgs/aiida-gaussian-datatypes { };
          cp2k-input-tools = pself.callPackage ../pkgs/cp2k-input-tools { };
          cp2k-output-tools = pself.callPackage ../pkgs/cp2k-output-tools { };
          # octopus is threaded in the same way xtb and crest are for aqme
          # above, and postopus runs it to generate its test fixtures.  Null
          # here just means a smaller suite, not a broken package.  Unlike xtb
          # and crest it *is* a top-level nixpkgs attribute, so the qchem
          # spelling is only a fallback for a set that has replaced it.
          #
          # `enableMpi = false` is the first of two things this build needs.
          # nixpkgs builds octopus with MPI by default, and OpenMPI cannot
          # initialise inside a nix build sandbox: there is no /sys, so hwloc
          # aborts topology discovery and UCX fails scanning /sys/class/net.
          # postopus invokes the binary directly rather than through mpirun —
          # see tests/utils/octopus_runner.py — so a serial build is what the
          # fixtures actually want, and this affects nothing but the check phase.
          #
          # netcdffortran is the second, and turning MPI off is what uncovered
          # it.  Every generating input in tests/data asks for
          # `OutputFormat = netcdf + vtk + plane_z + xcrysden`, and the octopus
          # nixpkgs builds answers that with
          #
          #     * Octopus was compiled without NetCDF support.
          #     * It is not possible to write output in NetCDF format.
          #
          # then exits 1, so all 68 tests downstream of a calculation error with
          # "Failed to run `octopus`".  nixpkgs puts the *C* library `netcdf` in
          # octopus' buildInputs, but CMakeLists.txt asks for
          # `find_package(netCDF-Fortran MODULE)`, whose find module resolves
          # `netcdf-fortran` through pkg-config.  That is a different derivation
          # — pkgs.netcdffortran — so it is never found, HAVE_NETCDF is never
          # set, and there is no OCTOPUS_NetCDF flag to force the issue.  Adding
          # it to buildInputs is the whole fix; pkg-config is already in
          # nativeBuildInputs.  Drop this once nixpkgs carries it.
          #
          # Neither failure prints anything to the build log, which is what made
          # both expensive to find: the inputs set `stdout = "gs_stdout.txt"` and
          # `stderr = "gs_stderr.txt"`, so octopus' own diagnostics go to files
          # in the run directory that pytest never reads.  To see them, run the
          # binary by hand in a copy of tests/data/methane with inp_gs as `inp`.
          postopus = pself.callPackage ../pkgs/postopus {
            octopus =
              let
                octopus' = final.octopus or final.qchem.octopus or null;
              in
              if octopus' == null then
                null
              else
                (octopus'.override { enableMpi = false; }).overrideAttrs (old: {
                  buildInputs = old.buildInputs ++ [ final.netcdffortran ];
                });
          };
          aiida-testing = pself.callPackage ../pkgs/aiida-testing { };

          # Test-only twice over: aiida-testing's own suite needs it, because
          # the `diff` entry points are what its mock_code tests mock.  Stops
          # here like the rest of them.
          aiida-diff = pself.callPackage ../pkgs/aiida-diff { };

          # Test-only, and only aiida-core's: the archive fixtures its
          # migration suite reads.  Like the other dependencies here it stops
          # at this step — no top-level alias, nothing in ../default.nix — so
          # ci.nix does not build it in its own right.
          aiida-export-migration-tests = pself.callPackage ../pkgs/aiida-export-migration-tests { };

          # See the `pymatgen` binding above for why that argument is threaded
          # in by hand rather than resolved through pself.
          #
          # `jq` is threaded in for a different reason: name collision.  Inside
          # a Python package set the name resolves to the *binding*,
          # python3.13-jq, and pself wins over final, so a defaulted `jq`
          # argument in the derivation quietly yields a package with no bin/jq.
          # PATH is then unchanged, and the one test that needs the program —
          # tests/calculations/test_stash.py, which writes a shell script that
          # pipes the calculation's JSON through it — fails with an assertion
          # about a missing output file.  The words "jq: command not found"
          # exist, but in the calcjob's _scheduler-stderr.txt inside the build
          # sandbox, never in the build log.  `final.jq` is the C program, whose
          # first output is `bin`.
          aiida-core = pself.callPackage ../pkgs/aiida-core {
            inherit pymatgen;
            inherit (final) jq;
          };

          # The six plugins.  Each finds its aiida-core through pself, so a
          # plugin and the core it extends are always the same derivation —
          # which is what makes entry-point discovery work when both land in one
          # python3.withPackages environment, the way
          # ../nixos-modules/aiida.nix builds one.
          #
          # aiida-gaussian is the odd one out: it needs cclib, which no
          # interpreter in this package set has.  It is a member here anyway
          # rather than a top-level entry alongside cheminformatics-cclib above,
          # because a plugin must come from the same set as the aiida-core it
          # extends — that is what entry-point discovery requires, and a
          # top-level `python3Packages.callPackage` would give it a *different*
          # aiida-core.  It therefore carries meta.broken on every path this repo
          # currently offers; see ../pkgs/aiida-gaussian/default.nix.
          aiida-cp2k = pself.callPackage ../pkgs/aiida-cp2k { };
          aiida-gaussian = pself.callPackage ../pkgs/aiida-gaussian { inherit pymatgen; };
          aiida-octopus = pself.callPackage ../pkgs/aiida-octopus { };
          aiida-orca = pself.callPackage ../pkgs/aiida-orca { };
          aiida-psi4 = pself.callPackage ../pkgs/aiida-psi4 { };
          aiida-quantumespresso = pself.callPackage ../pkgs/aiida-quantumespresso { };
        }
      )
    ];

    # Top-level aliases, for the same reason the qcfractal overlay has them:
    # lib.mkPackageOption pkgs "aiida-core" in ../nixos-modules/aiida.nix
    # resolves against the top level of pkgs, not a python package set.
    #
    # python313, the same interpreter the QCArchive set is pinned to, so the
    # repo carries two Python versions rather than three.  aiida-psi4 imports
    # qcelemental's v1 models, which become placeholder classes on 3.14 — see
    # ../pkgs/qcportal/default.nix for the mechanism — so following the default
    # python3 is not an option for this family either.  The one thing that did
    # not fit on 3.13 is pymatgen, handled at its callPackage site above.
    #
    # Keep this list and the interpreter in sync with the `inherit (py)` list in
    # ../default.nix; the aiida-overlay-python-pin eval test asserts they agree.
    #
    # The plugins are aliased for the same reason as aiida-core: they are what
    # `services.aiida.plugins` is given, and a NixOS configuration reaches them
    # as `pkgs.aiida-cp2k`, not through a Python package set.
    inherit (final.python313Packages)
      aiida-core
      aiida-cp2k
      aiida-gaussian
      aiida-octopus
      aiida-orca
      aiida-psi4
      aiida-quantumespresso
      ;
  };

  # Injects all QCArchive/QCFractal Python packages into every pythonX.pkgs
  # set via pythonPackagesExtensions.  This is what makes
  # python3.withPackages (p: [ p.qcfractal p.qcportal ... ]) work.
  #
  # pself is the fixed point of the *extended* Python package set, so
  # pself.qcportal inside the qcfractal derivation resolves to the local
  # package automatically — no manual inherit threading needed.
  qcfractal = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pself: _psuper: {
        parsl = pself.callPackage ../pkgs/parsl { };
        qcportal = pself.callPackage ../pkgs/qcportal { };
        qcfractal = pself.callPackage ../pkgs/qcfractal { };
        qcfractalcompute = pself.callPackage ../pkgs/qcfractalcompute { };
        qcarchivetesting = pself.callPackage ../pkgs/qcarchivetesting { };
      })
    ];

    # Top-level aliases. These are the *same* derivations as the entries in
    # python313Packages above (not rebuilds), and they are what
    # lib.mkPackageOption pkgs "qcfractal" in the NixOS modules resolves
    # against — without them, `services.qcfractal.package` fails with
    # "qcfractal cannot be found in pkgs" the moment a VM node or a real
    # system evaluates the module.
    #
    # python313 rather than python3: qcportal does not import on 3.14, which
    # nixpkgs-unstable now defaults to.  See pkgs/qcportal/default.nix for the
    # mechanism and ../default.nix for why following the default would break
    # the NixOS modules and the VM tests outright.
    #
    # Keep this list, and the interpreter, in sync with the `inherit (py)` list
    # in ../default.nix — the overlay-python-pin eval test asserts they agree.
    inherit (final.python313Packages)
      parsl
      qcportal
      qcfractal
      qcfractalcompute
      qcarchivetesting
      ;
  };
}
