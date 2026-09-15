{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  huggingface-hub,
  joblib,
  phonopy,
  pymatgen,
  scikit-learn,

  # optional-dependencies
  deepmd-kit ? null, # needs scikit-build-core >= 1, and nixos-26.05 has 0.11.6
  fairchem-core ? null, # needs e3nn, not in nixos-26.05
  mace-torch ? null, # not in nixos-26.05
  maml,
  matgl,
  matminer,
  phono3py,
  seekpath,
  sevenn ? null, # needs e3nn and matscipy, neither in nixos-26.05
  tensorpotential ? null, # needs matscipy, not in nixos-26.05

  # tests
  pytestCheckHook,
}:

# matcalc — property calculators (elasticity, EOS, phonons, NEB, MD…) that run
# on top of a machine-learned interatomic potential.  One of atomate2's
# follow-on targets in the materials chain (see "Deferred packaging" in
# ../../AGENTS.md).
buildPythonPackage (finalAttrs: {
  pname = "matcalc";
  version = "0.5.1-unstable-2026-09-09";
  pyproject = true;
  __structuredAttrs = true;

  # 84 commits past the v0.5.1 tag — dependabot bumps plus a few new model
  # configs; `version` is still 0.5.1 in pyproject.
  src = fetchFromGitHub {
    owner = "materialsvirtuallab";
    repo = "matcalc";
    rev = "b04715d37df27ff782f689f7a0ec36a66e08525c";
    hash = "sha256-k9JhJq2WhSFMX4IlmAAxz8blB4WpmceN8tUDlSyM59Q=";
  };

  # `oldest-supported-numpy` is a build-time pin for C extensions (matcalc has
  # none) and is gone from newer nixpkgs; the `setuptools < 82` cap is for
  # `maml`'s `pkg_resources` use, which is not in this closure.  `version` is a
  # plain string, so setuptools needs nothing else.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        'requires = ["oldest-supported-numpy", "setuptools>=58.0.3,<82"]' \
        'requires = ["setuptools"]'
  '';

  build-system = [ setuptools ];

  # `phonopy >= 4.2` is a hard requirement in the wheel metadata, and
  # nixos-26.05 carries phonopy 3.5.1 — `pythonRuntimeDepsCheckHook` fails there
  # before anything runs.  matcalc's phonopy use is version-agnostic (`import
  # phonopy`, `phonopy.file_IO.write_FORCE_CONSTANTS`, `pymatgen.io.phonopy`),
  # the same stable surface ../aiida-phonopy relaxes for the same reason.
  pythonRelaxDeps = [ "phonopy" ];

  dependencies = [
    ase
    huggingface-hub
    joblib
    phonopy
    pymatgen
    scikit-learn
  ];

  # Upstream's extras whose dependencies are packaged.  `mace` only where
  # `mace-torch` is (unstable, not 26.05); `fairchem` only where `e3nn` is,
  # which is the same two channels — ../../overlays/default.nix nulls
  # fairchem-core where it is not, and the note there says why that has to be
  # a null rather than a `meta.broken`; `phonon3` only where phonopy is 4.x,
  # since ../phono3py needs `phonopy >= 4.4` and 26.05 has 3.5.1.  Still
  # missing: `mattersim` / `orb` / `petmad`, which need NVIDIA's
  # `nvalchemi-toolkit-ops` the way torch-sim does — and with `fairchem` here
  # that is now the *only* thing keeping any matcalc backend out.
  #
  # `deepmd` and `fairchem` were both on that list until ../deepmd-kit and
  # ../fairchem-core landed, and neither belonged there: each was recorded as
  # blocked without its dependencies ever having been read against nixpkgs.
  # deepmd-kit needed one new package, fairchem-core two.
  #
  # `grace` is here but is the one extra a consumer cannot take for free:
  # ../tensorpotential is unfree, so asking for it needs `allowUnfree`.  It
  # reaches matcalc through this list alone — `nativeCheckInputs` below takes
  # only the `matgl` entry, so nothing about matcalc's own build touches it, and
  # matcalc stays buildable and cacheable as it was.
  #
  # `sevennet`, `grace` and `deepmd` join `fairchem` and `mace` in being
  # conditional, all of them because the overlay nulls the backend on
  # nixos-26.05 — but not all for the same reason, and the differences are the
  # interesting part.  ../sevenn declares `e3nn` and `matscipy` and
  # ../tensorpotential declares `matscipy`, names 26.05 does not have at all.
  # ../deepmd-kit is nulled over a *version*: `scikit-build-core>=1` against
  # that channel's 0.11.6.
  #
  # `deepmd` was left unconditional when the other two were made conditional,
  # on the reasoning that deepmd-kit wants `e3nn` for an extra of its own rather
  # than as a dependency and so survives 26.05.  That was true about e3nn and
  # wrong about the channel: it fails there for an unrelated reason, one that
  # evaluation cannot see and only a build reports.
  optional-dependencies = {
    phonon = [ seekpath ];
    benchmark = [ matminer ];
    maml = [ maml ];
    matgl = [ matgl ];
  }
  // lib.optionalAttrs (deepmd-kit != null) {
    deepmd = [ deepmd-kit ];
  }
  // lib.optionalAttrs (sevenn != null) {
    sevennet = [ sevenn ];
  }
  // lib.optionalAttrs (tensorpotential != null) {
    grace = [ tensorpotential ];
  }
  // lib.optionalAttrs (fairchem-core != null) {
    fairchem = [ fairchem-core ];
  }
  // lib.optionalAttrs (mace-torch != null) {
    mace = [ mace-torch ];
  }
  // lib.optionalAttrs (lib.versionAtLeast phonopy.version "4") {
    phonon3 = [ phono3py ];
  };

  # The suite is not run.  `tests/conftest.py` imports `matgl` at module scope
  # and its `matpes_calculator` fixture calls `matcalc.load_fp(...)`, which
  # downloads a model — and nearly every test needs a working calculator, so
  # every test needs the network.  Same shape as ../matgl and ../pubchempy.
  doCheck = false;

  nativeCheckInputs = [
    pytestCheckHook
  ]
  ++ finalAttrs.passthru.optional-dependencies.matgl;

  pythonImportsCheck = [
    "matcalc"
    "matcalc.utils"
    "matcalc._elasticity"
    "matcalc._phonon"
  ];

  meta = {
    description = "Calculators for materials properties from a machine-learned potential energy surface";
    homepage = "https://github.com/materialsvirtuallab/matcalc";
    license = lib.licenses.bsd3;
    mainProgram = "matcalc";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
