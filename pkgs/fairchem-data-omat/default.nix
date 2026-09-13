{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,
  hatch-vcs,
  hatch-fancy-pypi-readme,

  # dependencies
  pymatgen,

  # tests
  pytestCheckHook,
  ase,
  monty,
  numpy,
}:

# fairchem-data-omat — the VASP input set and the Materials-Project-style
# energy corrections behind the OMat24 dataset.  Here for `quacc`'s `fairchem`
# extra; internal, not re-exported.  See ../fairchem-data-omol for the
# monorepo arrangement the three data packages share.
buildPythonPackage (finalAttrs: {
  pname = "fairchem-data-omat";
  version = "0.2.0";
  pyproject = true;
  __structuredAttrs = true;

  # The tag is from 2025-11-14 and everything the repository has done to this
  # subtree since is copyright headers on four `__init__.py` files — so unlike
  # ../fairchem-data-oc there is nothing to gain by pinning past it.  One of
  # those headers does change something, and it is worth knowing which:
  # `tests/data/omat/compatibility_resources/__init__.py` does not exist at this
  # tag, which makes that directory a namespace package rather than a regular
  # one.  `test_compatibility.py` reaches its two JSON fixtures through
  # `importlib.resources.path`, and that resolves a single-location namespace
  # package fine on 3.13 and 3.14 alike.
  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "fairchem";
    tag = "fairchem_data_omat-${finalAttrs.version}";
    hash = "sha256-EV1mOdtLz3+p7b1GwgdKCVvZkcWFjkQsh49McCcBTvk=";
  };

  sourceRoot = "${finalAttrs.src.name}/packages/fairchem-data-omat";

  build-system = [
    hatchling
    hatch-vcs
    hatch-fancy-pypi-readme
  ];

  # See ../fairchem-data-omol; the `git_describe_command` here matches
  # `fairchem_data_omat-*` and is equally unreachable from a tarball.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `pymatgen>=2023.10.3` is the whole of it, and for once that is also the
  # whole of what the two modules import.  Both halves of this repository's
  # pymatgen split satisfy it; `entries/compatibility.py` needs `pymatgen`
  # proper for `pymatgen.entries.compatibility`, not just `pymatgen-core`.
  dependencies = [ pymatgen ];

  # ase and monty for the test module's own imports — `AseAtomsAdaptor` round
  # trips through real `ase.Atoms`, and the two JSON fixtures are `monty`
  # serialisations.  numpy comes along with pymatgen but is imported here in its
  # own right.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    monty
    numpy
  ];

  # The suite lives in `tests/` at the *repository* root, two levels above the
  # `sourceRoot` the wheel is built from, so reaching it is a `cd` rather than a
  # second build.  `src/` is not on `sys.path` from there — the tree is
  # `src/fairchem/...`, not `fairchem/...` — so the tests import the installed
  # package, which is the point.  ../fairchem-core does the same.
  #
  # **`tests/conftest.py` has to go, and this is the trap in running a monorepo's
  # sibling test tree.**  pytest loads every conftest.py on the path from its
  # rootdir down to the arguments, so that file applies to `tests/data/omat` as
  # much as to `tests/core` — and it belongs entirely to fairchem-core, opening
  # `import ray`, `import torch` and `import fairchem.core.common.gp_utils` at
  # module scope.  Keeping it would mean this two-module package dragging the
  # whole torch closure in as a check input to collect two files that need none
  # of it.
  #
  # Nothing here wants what it provides: it declares no autouse fixture, so
  # deleting it changes no RNG state and no per-test setup, and its hooks
  # (`--exclude-models` deselection, the `pretrained` and `gpu` markers) are
  # about pretrained checkpoints, which this suite never loads.
  # ../fairchem-data-oc removes it for the same reason.
  #
  # `chmod` before the `rm` because the unpack phase makes only `sourceRoot`
  # writable and `sourceRoot` is two directories down, so `tests/` — the
  # directory the removal needs write permission on, not the file — arrives
  # read-only.
  preCheck = ''
    cd ../..
    chmod -R u+w .
    rm tests/conftest.py
  '';

  enabledTestPaths = [ "tests/data/omat" ];

  # No POTCAR directory is needed despite this being a VASP input set: every
  # test that builds one passes `check_potcar=False` or names
  # `user_potcar_functional` explicitly, and none writes a POTCAR out.  That is
  # what separates this from ../vise, whose suite loses 23 tests to the same
  # licensed files.
  pythonImportsCheck = [
    "fairchem.data.omat"
    "fairchem.data.omat.entries.compatibility"
    "fairchem.data.omat.vasp.sets"
  ];

  meta = {
    description = "VASP input sets and energy corrections for the OMat24 dataset";
    homepage = "https://github.com/facebookresearch/fairchem";
    changelog = "https://github.com/facebookresearch/fairchem/releases/tag/fairchem_data_omat-${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
