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
  # ../flake.nix does that composition; see harmonwigPkgs there.
  harmonwig = final: _prev: {
    harmonwig = final.python3Packages.callPackage ../pkgs/harmonwig { };
  };

  # The AiiDA ecosystem: aiida-core, the five quantum chemistry plugins, and
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
      (pself: _psuper: {
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

        aiida-core = pself.callPackage ../pkgs/aiida-core {
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
          # Overridden here rather than in the extension above so that taking
          # overlays.aiida does not silently change pymatgen for everything else
          # in the consumer's package set.
          pymatgen = pself.pymatgen.overridePythonAttrs (_: {
            disabled = false;
          });
        };

        # The five plugins.  Each finds its aiida-core through pself, so a
        # plugin and the core it extends are always the same derivation —
        # which is what makes entry-point discovery work when both land in one
        # python3.withPackages environment, the way
        # ../nixos-modules/aiida.nix builds one.
        aiida-cp2k = pself.callPackage ../pkgs/aiida-cp2k { };
        aiida-octopus = pself.callPackage ../pkgs/aiida-octopus { };
        aiida-orca = pself.callPackage ../pkgs/aiida-orca { };
        aiida-psi4 = pself.callPackage ../pkgs/aiida-psi4 { };
        aiida-quantumespresso = pself.callPackage ../pkgs/aiida-quantumespresso { };
      })
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
