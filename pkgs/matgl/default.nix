{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  boto3,
  huggingface-hub,
  lightning,
  numpy,
  pydantic,
  pymatgen-core,
  torch,
  torch-geometric,
  torchdata,

  # tests
  pytestCheckHook,
}:

# MatGL — graph deep-learning models for materials (M3GNet, CHGNet, MEGNet).
# `emmet.core.similarity` uses it for `M3GNetSimilarity`, and `emmet-core`'s
# `test_similarity.py` guards on `matgl is None`; packaging it lets that module
# import.  atomate2's `forcefields` workflows want it too.
buildPythonPackage {
  pname = "matgl";
  version = "4.0.3-unstable-2026-09-03";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v4.0.3 tag, 23 behind it: the interim commits carry
  # real fixes — a periodic-structure crash in `neighbor_list_from_ase`, a
  # float64 fix in the spherical-Bessel basis, LAMMPS virial compatibility.
  src = fetchFromGitHub {
    owner = "materialyzeai";
    repo = "matgl";
    rev = "dcf5fd3713a3b6d2a1fdd81ac7885ffe5e149905";
    hash = "sha256-jDKY2w4sIz/aaX9lbMBFjxFbXq1Q94D/m9n2M78LekY=";
  };

  # `oldest-supported-numpy` is a build-time NumPy pin for projects with C
  # extensions; matgl has none (it is pure Python over torch), and the package
  # is long deprecated and gone from newer nixpkgs.  `version` is a plain string
  # in pyproject.toml, so setuptools needs nothing else.
  postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail \
            '    # pin NumPy version used in the build
        "oldest-supported-numpy",
    ' \
            ""
  '';

  build-system = [ setuptools ];

  # `lightning<=2.6.1` is relaxed for the channels' 2.6.5 — matgl uses the
  # stable `LightningModule` / `Trainer` surface, nothing that release touched.
  pythonRelaxDeps = [ "lightning" ];

  # `matgl/config.py` runs `MATGL_CACHE.mkdir(parents=True, exist_ok=True)` at
  # import — `MATGL_CACHE` is `~/.cache/matgl`, and the default
  # `/homeless-shelter` is not writable, so even `pythonImportsCheck` fails.
  # Same fix as ../pymatgen-core: a writable HOME set once, early, so the import
  # check and (were it enabled) the suite both see it.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  dependencies = [
    ase
    boto3
    huggingface-hub
    lightning
    numpy
    pydantic
    pymatgen-core
    torch
    torch-geometric
    torchdata
  ];

  # The suite is not run.  matgl's reason to exist is pretrained models, and
  # almost every test module calls `matgl.load_model`, which pulls weights from
  # the `materialyze` Hugging Face org — no network in the build sandbox, and
  # no bundled fixture models to fall back on.  The same shape as ../pubchempy.
  # `pythonImportsCheck` still exercises the whole torch / lightning /
  # torch-geometric closure, since `matgl/__init__` imports the training stack.
  doCheck = false;

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "matgl"
    "matgl.models"
    "matgl.ext.pymatgen"
  ];

  meta = {
    description = "Graph deep learning library for materials science";
    homepage = "https://github.com/materialyzeai/matgl";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
