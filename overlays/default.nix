# overlays/default.nix
#
# Exposed as the `overlays` reserved key in default.nix and re-exported
# by flake.nix as `self.overlays`.
#
# Each value is a standard  final: prev: { ... }  overlay function.
# Add new overlays here as additional attributes; default.nix composes
# them all via lib.composeManyExtensions.
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
      (pself: _psuper: {
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
    # xtb is threaded in by hand because neither spelling resolves on both
    # package sets this overlay is applied to: nixpkgs-unstable has it at the
    # top level and the nixpkgs NixOS-QChem pins does not, where it is
    # `qchem.xtb` from NixOS-QChem's own overlay instead.  The `or null` tail is
    # what keeps the attribute-path lookup from throwing on a set that has
    # neither; aqme then runs its non-xtb tests.
    aqme = final.python3.pkgs.callPackage ../pkgs/aqme {
      xtb = final.xtb or final.qchem.xtb or null;
    };
    ccreg = final.python3.pkgs.callPackage ../pkgs/ccreg { };
    dbstep = final.python3.pkgs.callPackage ../pkgs/dbstep { };
    digichem-core = final.python3.pkgs.callPackage ../pkgs/digichem-core { };
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
        pself: _psuper:
        let
          # nixpkgs carries `disabled = pythonAtLeast "3.13"` on pymatgen, so
          # `pkgs.python313Packages.pymatgen` throws at evaluation rather than
          # merely failing to build.  That gate is upstream nixpkgs being
          # conservative about an interpreter it has not tested, not pymatgen
          # refusing to run: lifting it instantiates and its whole closure
          # evaluates on 3.13 unchanged.
          #
          # It cannot simply be dropped instead.  aiida-quantumespresso depends
          # on `aiida_core[atomic_tools]`, pymatgen is in that extra, and the
          # alternative — pinning this whole family to 3.12 — would put a third
          # interpreter in the repo for the sake of one nixpkgs annotation.
          #
          # A `let` binding rather than a member of the attrset below, so that
          # taking overlays.aiida does not silently change pymatgen for
          # everything else in the consumer's package set.  It is passed
          # explicitly to the two packages that need it — aiida-core, and
          # aiida-gaussian, which depends on pymatgen directly.  The
          # aiida-overlay-pymatgen-override-is-local eval test asserts it stays
          # invisible from outside.
          pymatgen = pself.pymatgen.overridePythonAttrs (_: {
            disabled = false;
          });
        in
        {
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

          # Plugin dependencies, likewise missing from nixpkgs and likewise not
          # re-exported.  aiida-testing is test-only — it is what supplies
          # aiida-psi4's mock_code fixture — but it lives here rather than in a
          # checkInputs-only position because pself is the only thing that can
          # resolve its own aiida-core to the same derivation.
          qe-tools = pself.callPackage ../pkgs/qe-tools { };
          aiida-pseudo = pself.callPackage ../pkgs/aiida-pseudo { };
          aiida-gaussian-datatypes = pself.callPackage ../pkgs/aiida-gaussian-datatypes { };
          cp2k-output-tools = pself.callPackage ../pkgs/cp2k-output-tools { };
          postopus = pself.callPackage ../pkgs/postopus { };
          aiida-testing = pself.callPackage ../pkgs/aiida-testing { };

          # See the `pymatgen` binding above for why this one argument is
          # threaded in by hand rather than resolved through pself.
          aiida-core = pself.callPackage ../pkgs/aiida-core { inherit pymatgen; };

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
