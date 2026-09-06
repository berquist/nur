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
  mace-torch ? null, # not in nixos-26.05
  maml,
  matgl,
  matminer,
  phono3py,
  seekpath,
  sevenn,

  # tests
  pytestCheckHook,
}:

# matcalc — property calculators (elasticity, EOS, phonons, NEB, MD…) that run
# on top of a machine-learned interatomic potential.  One of atomate2's
# follow-on targets in the materials chain (see "Deferred packaging" in
# ../../AGENTS.md).
buildPythonPackage (finalAttrs: {
  pname = "matcalc";
  version = "0.5.1-unstable-2026-09-03";
  pyproject = true;
  __structuredAttrs = true;

  # 84 commits past the v0.5.1 tag — dependabot bumps plus a few new model
  # configs; `version` is still 0.5.1 in pyproject.
  src = fetchFromGitHub {
    owner = "materialsvirtuallab";
    repo = "matcalc";
    rev = "ce5e92cef1a3231e5a10dd9cff69a4264d5ad0c0";
    hash = "sha256-Iyvt0OgfFsyBit1swp8o9Hzb8J6txbcXRwDm20WpCKA=";
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
  # `mace-torch` is (unstable, not 26.05); `phonon3` only where phonopy is 4.x,
  # since ../phono3py needs `phonopy >= 4.4` and 26.05 has 3.5.1.  Still
  # missing: `grace` (tensorpotential), `deepmd` (deepmd-kit), `fairchem`
  # (fairchem-core), and `mattersim` / `orb` / `petmad`, which need NVIDIA's
  # `nvalchemi-toolkit-ops` the way torch-sim does.
  optional-dependencies = {
    phonon = [ seekpath ];
    benchmark = [ matminer ];
    maml = [ maml ];
    matgl = [ matgl ];
    sevennet = [ sevenn ];
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
