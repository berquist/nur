{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  braceexpand,
  e3nn,
  lmdb,
  matscipy,
  ninja,
  numpy,
  orjson,
  pandas,
  pyyaml,
  requests,
  scikit-learn,
  torch-geometric,
  tqdm,

  # tests
  pytestCheckHook,
  pytest-cov,
}:

# SevenNet — an equivariant graph neural-network interatomic potential, one of
# matcalc's ML-potential backends (`matcalc[sevennet]`).  The `sevenn/
# pretrained_potentials/*.pth` checkpoints (53 MB) ship in the package, so
# `7net-0` and friends work with no download.
buildPythonPackage {
  pname = "sevenn";
  version = "0.13.0-unstable-2026-07-22";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "MDIL-SNU";
    repo = "SevenNet";
    rev = "8d9905cc4f4b7ca93be02b37a263785add53c759";
    hash = "sha256-QT6JFZ11WzzFLBX3tL51GtrtP9lQMZgPE2+UVfxcjco=";
  };

  build-system = [ setuptools ];

  # `lmdb < 2.0.0` is honoured rather than relaxed.  This once said "nothing
  # 2.x changed", which was wrong: 2.0.0 made a second `open()` of an
  # already-open environment path an error, and SevenNet is the third project
  # here to cap below it.  The overlay pins py-lmdb to 1.7.3, so the bound is
  # satisfied as written — see the `lmdb` binding in ../../overlays.

  # The `.cpp` files under `sevenn/pair_e3gnn/` are LAMMPS pair styles, built
  # against a LAMMPS tree by its users, not part of this wheel — setup.py
  # declares no extension.
  dependencies = [
    ase
    braceexpand
    e3nn
    lmdb
    matscipy
    ninja
    numpy
    orjson
    pandas
    pyyaml
    requests
    scikit-learn
    torch-geometric
    tqdm
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
  ];

  # Only the unit tests.  `tests/lammps_tests` needs a LAMMPS build.
  enabledTestPaths = [ "tests/unit_tests" ];

  # The cuEquivariance / OpenEquivariance / flash-attention accelerators
  # (NVIDIA CUDA wheels) and torch-sim are not packaged; these modules import
  # them at collection scope rather than guarding.
  #
  # `test_pretrained.py` is the network one: all eleven of its tests reach
  # `pretrained_name_to_path`, which fetches a checkpoint from github.com, so
  # every one of them fails with a `ConnectionError` in the build sandbox.  Same
  # decision as ../matgl, ../matcalc and ../mp-api.
  disabledTestPaths = [
    "tests/unit_tests/test_cueq.py"
    "tests/unit_tests/test_oeq.py"
    "tests/unit_tests/test_flash.py"
    "tests/unit_tests/test_pretrained.py"
    "tests/unit_tests/test_torchsim.py"
  ];

  pythonImportsCheck = [
    "sevenn"
    "sevenn.calculator"
  ];

  meta = {
    description = "Scalable EquivariancE-Enabled Neural Network interatomic potential";
    homepage = "https://github.com/MDIL-SNU/SevenNet";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
