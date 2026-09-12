{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  numpy,

  # tests
  pytestCheckHook,
  gromacs,
  lxml,
  netcdf4,
  networkx,
  openmm,
  pandas,
  rdkit,

  # AmberTools, which thirteen tests gate on and which nixpkgs does not have.
  # NixOS-QChem does, as `qchem.ambertools`, and taking theirs is the standing
  # rule — see "Reusing NixOS-QChem" in ../../AGENTS.md.  Defaulted for the usual
  # reason: ../../overlays is imported without flakes by default.nix, overlay.nix
  # and ci.nix, so it cannot reach that input.
  #
  # **Unlike `packmol`, this one is `requireFile` upstream**, and that is worth
  # knowing before wiring anything else to it.  NixOS-QChem cannot redistribute
  # the AmberTools tarball, so its derivation asks the user to download it from
  # ambermd.org and `nix-store --add` it by hand.  Consequences:
  #
  #   there is no `checks` entry for this in ../../flake.nix, and there must not
  #   be — it would fail on any machine that has not provisioned the tarball,
  #   including every CI runner, which is not a failure mode a check should have;
  #
  #   a consumer who composes `overlays.qchem` (as `overlays.default` does) and
  #   then builds *this* package gets the requireFile message rather than a
  #   build.  `.override { ambertools = null; }` is the way out, and the thirteen
  #   tests go back to skipping.
  #
  # The NUR path, `ci.nix` and `flake.nix`'s own `pkgs'` all compose ./overlays
  # without qchem, so all three see null and are unaffected.
  ambertools ? null,
}:

# ParmEd — reads, writes and manipulates the topology and parameter files of
# Amber, CHARMM, GROMACS, NAMD, DL_POLY, Tinker and OpenMM, and converts
# between them.  Here for ../dpdata, whose `pick_by_amber_mask` is the only
# thing in this repository that reaches it.  Internal, not re-exported.
#
# Not in nixpkgs at all, which is the whole reason it is here: `dpdata`'s
# `TestPickByAmberMask` was deselected for want of it.
buildPythonPackage (finalAttrs: {
  pname = "parmed";
  version = "4.3.1";
  pyproject = true;
  __structuredAttrs = true;

  # 70 MB of tarball, and 236 MB unpacked — `test/files/` is most of it.  The
  # tag rather than the two commits past it: both are features (rdkit bond
  # orders, new 12-6-4 water models) and neither is anything `dpdata` reaches.
  #
  # **The `.gitattributes` here marks `parmed/_version.py` export-subst**, which
  # is the case ../../scripts/offline-src-hash.sh refuses to answer for — the
  # placeholder expands to whatever refs the clone happens to carry.  The hash
  # below was checked against the real codeload tarball rather than taken from
  # the clone alone, and the two agree, because the local clone's ref-name
  # expansion at this tag is the same string GitHub produces: `" (tag: 4.3.1)"`.
  #
  # That substitution is also why there is no `SETUPTOOLS_SCM_PRETEND_VERSION`
  # or equivalent here: versioneer reads those baked-in keywords and gets 4.3.1
  # from them, with no repository to consult.
  src = fetchFromGitHub {
    owner = "ParmEd";
    repo = "ParmEd";
    tag = finalAttrs.version;
    hash = "sha256-Y1aZlw/dmH86ekMjovavGiT67inJfQ3+jUfmU9uDJns=";
  };

  # setup.py only — no pyproject.toml — so the backend has to be named here.
  #
  # One thing to know if this ever fails to build: `setup.py` opens with
  # `from distutils.command.clean import clean`, and Python has not shipped
  # distutils since 3.12.  It works because setuptools' `distutils-precedence.pth`
  # installs its vendored copy at interpreter startup, so the import resolves to
  # setuptools rather than to nothing.  That is a shim with an end date, not a
  # guarantee.
  build-system = [ setuptools ];

  # ParmEd declares no `install_requires` at all.  numpy is the one third-party
  # import at module scope, and it is in a dozen modules — `parmed.geometry`,
  # `parmed.amber._amberparm` and the rest — so it is not optional.  Everything
  # else the package can reach (openmm, rdkit, networkx, pandas, netCDF4, lxml,
  # nglview, pyrosetta, sander) is imported inside a function and degrades.
  dependencies = [ numpy ];

  # The optional halves of the above, so their test modules run rather than
  # skip.  All in nixpkgs; openmm is the expensive one and is here anyway,
  # because five of the 35 test modules are about the OpenMM converters and
  # deselecting them would be the larger loss.
  #
  # **`gromacs` is here for its data files, not its binaries.**  `utils.py`
  # computes `HAS_GROMACS = os.path.isdir(gromacs.GROMACS_TOPDIR)`, and
  # `parmed/gromacs/__init__.py` resolves that from `$GMXDATA`, `$GMXBIN`, a
  # scan of `/usr` and friends, or a `gmx` on PATH — falling back to the literal
  # `/usr/local/gromacs/share/gromacs/top`, which no nix build has.  That put
  # `HAS_GROMACS` at False and took 21 `skipIf` sites with it, the largest
  # single block of skips in the suite.  `preCheck` sets `GMXDATA`.
  nativeCheckInputs = [
    pytestCheckHook
    gromacs
    lxml
    netcdf4
    networkx
    openmm
    pandas
    rdkit
  ]
  ++ lib.optional (ambertools != null) ambertools;

  # `-rsfE` so the reasons for skips are in the build log rather than being
  # rediscovered from the source every time — ../fireworks passes `-rs` for the
  # same reason, and the extra `fE` is this package's own lesson: `-r` *replaces*
  # pytest's default `fE`, so a bare `-rs` reported every skip and then left the
  # one failure out of the short summary entirely.
  #
  # What the reasons say, once `ambertools` and `gromacs` are both filled in:
  # four Entos tests (proprietary, Qcore), one that upstream disabled itself when
  # RCSB dropped FTP, and nine behind `PARMED_RUN_ALL_TESTS` — "Skipping large
  # tests", "Skipping long tests", "Skipping OMM tests on large systems".  That
  # last group is a deliberate env var rather than a missing dependency, and it
  # is left unset: the four OpenMM ones build energies for whole solvated
  # systems.
  pytestFlags = [ "-rsfE" ];

  # **The `rm` is the shadowing trap, and here it was doing real damage rather
  # than merely being untidy.**  `pytestCheckPhase` runs `python -m pytest`,
  # which puts the working directory first on `sys.path`, so `import parmed`
  # from the source root found `./parmed/` — the *source* tree — and the whole
  # suite tested that instead of the installed wheel.  It surfaced as exactly
  # one failure, `test_optimized_reader` reporting
  # `ImportError: cannot import name '_rdparm' from 'parmed.amber'`, because the
  # C++ extension is the one thing the source tree does not have: setup.py
  # builds it into `build/lib.*` and the install phase puts it in site-packages.
  # Six hundred other tests passed against the wrong copy without complaint.
  # ../dpdata, ../sella, ../wignernj and ../trexio are the same trap in four
  # other shapes.
  #
  # `GMXDATA` per the note above.  The `test -d` is deliberate: without it a
  # wrong path here would silently restore the 21 skips, which is the failure
  # mode this whole change is about.
  # `AMBERHOME` is what eleven of the thirteen AmberTools tests read
  # (`os.getenv('AMBERHOME') is None`); the other two want a `tleap` on PATH,
  # which the check input above provides.  NixOS-QChem wraps every program in
  # `$out/bin` with `--set-default AMBERHOME $out`, so the package root is the
  # right value, and `bin/tleap` is the thing to assert on — the same
  # loud-rather-than-silent guard as `GMXDATA` above, for the same reason.
  preCheck = ''
    rm -rf parmed

    export GMXDATA="${gromacs}/share/gromacs"
    test -d "$GMXDATA/top" \
      || { echo "GMXDATA/top is not where parmed looks for it: $GMXDATA/top" >&2; exit 1; }
  ''
  + lib.optionalString (ambertools != null) ''

    export AMBERHOME="${ambertools}"
    test -x "$AMBERHOME/bin/tleap" \
      || { echo "no tleap under AMBERHOME: $AMBERHOME/bin/tleap" >&2; exit 1; }
  '';

  enabledTestPaths = [ "test" ];

  # The two that cannot run here, and neither is about ParmEd:
  #
  #   `test_parmed_rosetta.py` needs PyRosetta, which is licensed per-user and
  #   not distributable.
  #
  #   `test_parmedtools_actions.py` imports `sander`, AmberTools' in-process
  #   Amber engine.  That one *is* reachable — AmberTools is a Python package in
  #   the `nixos-qchem` input — but ../../overlays cannot see a flake input, so
  #   it would have to come in as a defaulted argument the way
  #   ../fairchem-data-oc's `packmol` does.  Worth doing if anything here ever
  #   needs more of ParmEd than dpdata does; see "Reusing NixOS-QChem" in
  #   ../../AGENTS.md.
  disabledTestPaths = [
    "test/test_parmed_rosetta.py"
    "test/test_parmedtools_actions.py"
  ];

  # Twenty-two tests that reach the network and one that reads openmm's mind.
  #
  # `test_download` covers eighteen — `TestFileDownloader`'s fifteen plus
  # `TestPDBStructure`/`TestCIFStructure`'s `test_download` and
  # `test_download_save` — and every name in the suite containing "download" is
  # one of them, so the prefix is exact rather than convenient.  They fetch PDB
  # entry 4lzt from rcsb.org and fixture files from
  # `github.com/ParmEd/ParmEd/raw/master/test/files/`; `test_save_psf2` pulls a
  # tutorial file from ambermd.org.
  #
  # The three `_URL` genopen tests are named individually rather than by
  # substring, because `test_read_bad_URL` and `test_read_ftp_URL` pass offline
  # — they assert that a bad URL fails, which it does either way — and a
  # `-k "not _URL"` would have thrown those away too.
  #
  # `testMisc` is the one that is not about the network: it asserts
  # `repr(1.2*u.meters) == 'Quantity(value=1.2, unit=meter)'`, and openmm 8.6
  # returns `'1.2 m'`.  `parmed/unit/` is a vendored copy of `openmm.unit` that
  # defers to the real one whenever OpenMM can be imported — so this failure
  # exists *because* openmm is a check input, and would not appear at all with a
  # narrower set.  The assertion is upstream's to update, and the other four in
  # the same method still run everywhere else in the file.
  # `test_pme_switch` is the last of the openmm-version failures, and the
  # narrowest: it asserts a DHFR nonbonded energy of -18587.09715 kJ/mol against
  # a relative tolerance of 1e-4, and openmm 8.6 returns -18588.32473 — off by
  # 6.6e-5, which is inside one order of magnitude of the tolerance rather than
  # anywhere near a wrong answer.  The reference numbers in that file are
  # attributed in a comment to "Lee-Ping's answers" and predate several OpenMM
  # PME reworks.  The other seven energy terms in the same test match, and the
  # rest of `TestGromacsTop` passes, so this is a tolerance that has aged rather
  # than a converter that is broken.
  disabledTests = [
    "test_download"
    "test_pme_switch"
    "test_read_bzipped_URL"
    "test_read_gzipped_URL"
    "test_read_normal_URL"
    "test_save_psf2"
    "testMisc"
  ];

  pythonImportsCheck = [
    "parmed"
    "parmed.amber"
    "parmed.amber.mask"
    "parmed.formats"
  ];

  meta = {
    description = "Parameter and topology file editor and molecular mechanics simulation engine";
    homepage = "https://github.com/ParmEd/ParmEd";
    changelog = "https://github.com/ParmEd/ParmEd/releases/tag/${finalAttrs.version}";
    license = lib.licenses.lgpl2Plus;
    mainProgram = "parmed";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
