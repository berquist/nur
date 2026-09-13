{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,

  # dependencies
  ase,
  h5py,
  numba,
  numpy,
  pandas,
  scipy,
  spglib,
  sympy,
  trainstation,

  # tests
  pytestCheckHook,
  pytest-xdist,
}:

# hiPhive — high-order force constants fitted from supercell displacements.
# Here as `shakenbreak`'s dependency, whose `mc_rattle` is what shakenbreak
# perturbs defect structures with; see "Deferred packaging" in ../../AGENTS.md
# for the rest of that cluster.  Internal, not re-exported.
#
# Distribution `hiPhive`, import `hiphive`.
buildPythonPackage {
  pname = "hiphive";
  version = "1.5-unstable-2026-06-18";
  pyproject = true;
  __structuredAttrs = true;

  # GitLab, like ../trainstation and for the same reason — same group.  HEAD,
  # 24 commits past the `1.5` tag; the version attribute upstream reads is
  # still `1.5`.
  src = fetchFromGitLab {
    owner = "materials-modeling";
    repo = "hiphive";
    rev = "04a715ea641189ca8af34888737ec8a1377e536f";
    hash = "sha256-qZ/xVU8MDYWP47QdN+yrMGewQpf/vvGJkDj43nfa4BU=";
  };

  build-system = [ setuptools ];

  # ../trainstation is the only one nixpkgs does not carry, and it is why that
  # package is in this repository at all.
  dependencies = [
    ase
    h5py
    numba
    numpy
    pandas
    scipy
    spglib
    sympy
    trainstation
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
  ];

  # `tests/unittests` only.  `tests/integration` is a different thing despite
  # the `test_*.py` names: those files are scripts that upstream's own
  # `tests/main.py` runs by `exec`, fitting real force-constant models over
  # numba-compiled loops, and they take minutes each rather than seconds.
  # The unit tests cover the same code paths on toy cells.
  enabledTestPaths = [ "tests/unittests" ];

  pythonImportsCheck = [
    "hiphive"
    "hiphive.structure_generation"
  ];

  meta = {
    description = "High-order force constants for the masses";
    homepage = "https://gitlab.com/materials-modeling/hiphive";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
