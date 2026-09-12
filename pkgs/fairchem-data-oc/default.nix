{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  fetchurl,
  python,

  # build-system
  hatchling,
  hatch-vcs,
  hatch-fancy-pypi-readme,

  # dependencies
  ase,
  fairchem-core,
  matplotlib,
  numpy,
  pymatgen,
  scipy,
  tqdm,

  # tests
  pytestCheckHook,

  # packmol, which `core/interface_config.py` shells out to through
  # `shutil.which("packmol")` when it fills a solvent box.  Upstream declares it
  # nowhere — it is a `which` call and an `OSError` if it is missing — so a
  # consumer who wants `InterfaceConfig` has to put it on PATH themselves; this
  # is here for the two tests that exercise that class.
  #
  # Defaulted, and unlike ../postopus's `octopus` it is null on the ordinary
  # path rather than only on an unusual one: **packmol is not in nixpkgs at
  # all.**  NixOS-QChem has it as `qchem.packmol`, which is where it comes from
  # — see "Reusing NixOS-QChem" in ../../AGENTS.md — and `overlays/` is imported
  # without flakes by default.nix, overlay.nix and ci.nix, so it cannot reach
  # that input, the same constraint that makes cclib a flake-only dependency
  # here.  ../../overlays/default.nix picks whichever spelling the package set
  # has, so composing `overlays.qchem` beside `overlays.materials` turns the two
  # tests below back on; `checks.fairchem-data-oc` in ../../flake.nix is this
  # repository's own way of doing that, and the only path here that runs them.
  packmol ? null,
}:

let
  # The OC20 bulk database: 11k bulk structures, 36 MB, and the thing four of
  # this package's six classes are built around.  It is not in the repository —
  # upstream keeps it out and fetches it on first use, from
  # `fairchem.core.scripts.download_large_files`, into the *installed* package
  # directory.  Neither half of that works here: a build has no network, and the
  # store path it would write to is read-only afterwards.
  #
  # So it is fetched as a fixed-output derivation and installed alongside the
  # three `.pkl` files that are in the repository.  `Bulk.__init__` only
  # downloads `if not os.path.exists(BULK_PKL_PATH)`, so putting the file there
  # is the whole fix — no patch, and no behaviour left to differ between this
  # build and a pip install that has already run once.
  #
  # The URL is `S3_ROOT + file.name`, note, not `S3_ROOT + str(file)`: the
  # path in `FILE_GROUPS` names where the file *lands*, and only its basename
  # goes into the request.
  #
  # Without this, six of the seven test modules here are dead — every one of
  # them opens the bulk database in a class fixture — which is exactly the
  # green-build-that-tested-nothing shape ../../AGENTS.md warns about.
  bulksPkl = fetchurl {
    url = "https://dl.fbaipublicfiles.com/opencatalystproject/data/large_files/bulks.pkl";
    hash = "sha256-yBAvKHqhGr0R6yEPKP8P2jwwUz4MShttnEw4JUghud4=";
  };
in

# fairchem-data-oc — adsorbate/catalyst structure generation: bulks, slabs,
# adsorbate placements, solvent and ionic interfaces, and the VASP flags that
# built OC20.  Here for `quacc`'s `fairchem` extra; internal, not re-exported.
# See ../fairchem-data-omol for the monorepo arrangement the three data
# packages share.
buildPythonPackage (finalAttrs: {
  pname = "fairchem-data-oc";
  version = "1.0.2-unstable-2026-09-04";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD rather than the `fairchem_data_oc-1.0.2` tag, which is the odd one out
  # among the three data packages and for a concrete reason: that tag is from
  # 2025-08-22, and the six commits to this subtree since are precisely the
  # catch-up with everything this repository already carries — numpy 1.26+
  # compatibility, the pymatgen slab-generation change, `safe_pickle_load` in
  # place of a bare `pickle.load`, and a `pp_version` VASP flag.  The pymatgen
  # one is a *test* fix and would fail here as an assertion rather than as
  # anything that reads like a version problem: d48457d, "update tests per
  # pymatgen update", changes one expected formula from `Sn48` to `Sn24`.
  #
  # `quacc[fairchem]` asks for `fairchem-data-oc>=1.0.2`, which the pretend
  # version below satisfies exactly; this is past that release, not short of it.
  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "fairchem";
    rev = "e3d2d7c42692a993605f109011dd65458c46f2f5";
    hash = "sha256-aSXqCxBYG16kCvoZ5Y0AAZFSaTKm9XzchdPy50sPF1I=";
  };

  sourceRoot = "${finalAttrs.src.name}/packages/fairchem-data-oc";

  build-system = [
    hatchling
    hatch-vcs
    hatch-fancy-pypi-readme
  ];

  # See ../fairchem-data-omol.  The `-unstable-` suffix is not PEP 440, so only
  # the part before the first dash goes in — the same shape as ../cmcrameri and
  # ../pymatgen.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  # `fairchem-core` is the undeclared one, and it is not optional:
  # `core/bulk.py` opens `from fairchem.core.common.safe_pickle import
  # safe_pickle_load` and `from fairchem.core.scripts import
  # download_large_files` at module scope, and `databases/update.py` does the
  # same.  `fairchem.data.oc.core` cannot be imported without it.
  #
  # It does not run the other way — ../fairchem-core's two imports of
  # `fairchem.data.oc` both sit inside `try:` blocks — so this is a dependency
  # rather than a cycle.  The one cross-package import in that direction that is
  # *not* guarded reaches ../fairchem-data-omol, not this package.
  #
  # Everything else here is declared upstream, and no bound needs relaxing: they
  # are all floors (`ase>=3.27`, `numpy>=2.0`, `scipy>=1.15.0`,
  # `pymatgen>=2023.10.3`) and the channels here are past every one.
  dependencies = [
    ase
    fairchem-core
    matplotlib
    numpy
    pymatgen
    scipy
    tqdm
  ];

  # See the note above `bulksPkl`.  `install -D` creates the intermediate
  # directories; the file lands beside the `adsorbates.pkl`, `ions.pkl` and
  # `solvents.pkl` that hatchling copied out of the repository, which is where
  # `databases/pkls/__init__.py` computes `BULK_PKL_PATH` from `__path__[0]`.
  postInstall = ''
    install -Dm444 ${bulksPkl} \
      "$out/${python.sitePackages}/fairchem/data/oc/databases/pkls/bulks.pkl"
  '';

  # `fairchem/core/_config.py` runs `os.makedirs(CACHE_DIR, exist_ok=True)` at
  # module scope under `~/.cache`, so importing this package at all — it reaches
  # `fairchem.core` through `core/bulk.py` — fails on stdenv's unwritable
  # `/homeless-shelter`.  In `preBuild` rather than `preCheck` because
  # `pythonImportsCheck` is what trips it and that runs outside the check phase;
  # ../fairchem-core, ../matgl and ../maml all carry the same three lines.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  nativeCheckInputs = [
    pytestCheckHook
  ]
  ++ lib.optional (packmol != null) packmol;

  # **`pytest-xdist` must never be added here**, and unusually the reason is a
  # single module rather than a suite-wide habit: `test_bulk.py`'s
  # `test_unique_slab_enumeration` pickles its slabs to `0.pkl` in the working
  # directory and `test_precomputed_slab` reads that file back and deletes it.
  # Two tests, one file, and no fixture between them — they pass only in
  # declaration order in one process.  ../doped, ../shakenbreak and ../fireworks
  # carry the same prohibition for broader reasons.
  #
  # `chmod -R u+w` for that same `0.pkl`, and for the `rm` below: the unpack
  # phase makes only `sourceRoot` writable and `sourceRoot` is two directories
  # down, so the tree this `cd` moves into is read-only.  See ../fairchem-core,
  # where the same omission surfaced as a bare `assert False is True`.
  #
  # `tests/conftest.py` is fairchem-core's, and pytest would apply it here
  # because it sits on the path from the rootdir down to these arguments.  It
  # imports ray, torch and `fairchem.core.common.gp_utils` at module scope —
  # all reachable from this package, unlike ../fairchem-data-omat, so removing
  # it is a tidiness rather than a necessity.  It is still the right call: it
  # declares no autouse fixture and every hook in it is about pretrained
  # checkpoints, so it contributes nothing to a suite that only builds
  # structures, while making each session import the whole torch stack.  See
  # ../fairchem-data-omat, where the same file is load-bearing in the other
  # direction.
  preCheck = ''
    cd ../..
    chmod -R u+w .
    rm tests/conftest.py
  '';

  enabledTestPaths = [ "tests/data/oc/tests" ];

  # Seven modules collect out of that path for 34 tests, and `old_tests/`
  # beneath it contributes none — it is a 2020-era harness of bare scripts
  # (`RUN_unittest.sh`, `check_energy_and_forces.py`, `verify_correctness.py`)
  # driven from a shell, and not one of its filenames matches pytest's default
  # `python_files`.  Nothing has to exclude it, but it is worth knowing it is
  # there before reading the collected count as the whole directory.
  #
  # 30 pass, and two of `test_bulk.py`'s xfail themselves on a pymatgen slab
  # bug upstream has an open issue for (materialsproject/pymatgen#3747) — both
  # assert 14 slabs and accept 15 as a known-wrong answer.  Those two are the
  # canary for the pin past the tag: they are the *later* half of the same
  # slab-generation drift that makes the tagged `Sn48` wrong.
  #
  # The remaining two are `test_interface_config.py`, and they need packmol on
  # PATH rather than anything importable.  See the `packmol` argument above:
  # this deselects the module only when there is none to be had, so a set that
  # composes `overlays.qchem` runs the whole suite.
  disabledTestPaths = lib.optionals (packmol == null) [
    "tests/data/oc/tests/test_interface_config.py"
  ];
  pythonImportsCheck = [
    "fairchem.data.oc"
    "fairchem.data.oc.core"
    "fairchem.data.oc.utils.vasp"
  ];

  meta = {
    description = "Adsorbate and catalyst structure generation for the Open Catalyst datasets";
    homepage = "https://github.com/facebookresearch/fairchem";
    # Two entries, because the output carries more than the code: `ocdata` is
    # MIT, and the bulk database installed above is part of OC20, which is
    # released under CC BY 4.0.  Both are free, so `ci.nix`'s licence filter —
    # which handles a list — still passes this.
    license = with lib.licenses; [
      mit
      cc-by-40
    ];
    maintainers = with lib.maintainers; [ berquist ];
  };
})
