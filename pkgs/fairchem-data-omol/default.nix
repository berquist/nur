{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,
  hatch-vcs,
  hatch-fancy-pypi-readme,

  # dependencies
  ase,
  numpy,
  pymatgen,
  scipy,

  # optional-dependencies
  sella,
}:

# fairchem-data-omol — the ORCA input generators and evaluation helpers behind
# the OMol25 dataset.  Here for `quacc`'s `fairchem` extra, which names it
# beside ../fairchem-data-oc, ../fairchem-data-omat and ../fairchem-core.
# Internal, not re-exported.
#
# The second distribution taken out of the thirteen-package `fairchem`
# monorepo, on the same arrangement as ../fairchem-core: `packages/<name>/`
# holds a pyproject.toml and a `src -> ../../src` symlink, and the wheel's
# `only-include` narrows that to one subtree.  What the three data packages
# have that fairchem-core does not is a *shared* import path — none of them
# ships `fairchem/__init__.py` or `fairchem/data/__init__.py`, so `fairchem`
# and `fairchem.data` are PEP 420 namespace packages and the four
# distributions merge in a `withPackages` the way ../pymatgen-core and
# ../pymatgen do.
buildPythonPackage (finalAttrs: {
  pname = "fairchem-data-omol";
  version = "0.1.2";
  pyproject = true;
  __structuredAttrs = true;

  # Per-distribution tags, so `fairchem_data_omol-0.1.2` rather than a bare
  # version.  This one is content-identical to the repository HEAD it was cut
  # from, unlike ../fairchem-data-oc's, which is a year behind.
  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "fairchem";
    tag = "fairchem_data_omol-${finalAttrs.version}";
    hash = "sha256-B8tRvfU/p5QXJ509rnemcTibckqcvHJeeyzhnSG4NlI=";
  };

  sourceRoot = "${finalAttrs.src.name}/packages/fairchem-data-omol";

  build-system = [
    hatchling
    hatch-vcs
    hatch-fancy-pypi-readme
  ];

  # hatch-vcs is setuptools-scm underneath and there is no repository to read;
  # `[tool.hatch.version.raw-options]` additionally points `root` at `../../`
  # with a `git_describe_command` matching `fairchem_data_omol-*`, neither of
  # which survives an unpacked tarball.  Same shape as ../fairchem-core.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # Upstream declares `ase` and nothing else.  Three more are imported at module
  # scope in library code, so the modules holding them cannot be imported
  # without them:
  #
  #   numpy, scipy, pymatgen   modules/evaluator.py — `MSONAtoms` and
  #                            `linear_sum_assignment` are both module-scope
  #
  # ../vise's lesson again: what a project declares is not what it imports.
  dependencies = [
    ase
    numpy
    pymatgen
    scipy
  ];

  # `orca/recipes.py` imports `quacc.recipes.orca._base` and `psutil` at module
  # scope, and **neither is declared here on purpose.**  quacc is the package
  # whose `fairchem` extra pulls this one in, so declaring it would be a cycle
  # nix cannot express — the same shape as ../doped and ../shakenbreak, and cut
  # the same way: the half that declares the other keeps the requirement, and
  # this half drops it.  Upstream has already made that choice for us by leaving
  # both out of `dependencies`; a consumer that wants those four wrappers is
  # installing quacc anyway, which brings psutil with it.
  #
  # This is why `orca.recipes` is absent from `pythonImportsCheck` below.
  optional-dependencies = {
    extras = [ sella ];
  };

  # Upstream ships no tests for this distribution: `tests/` at the repository
  # root carries `core`, `oc`, `omat`, `applications`, `demo`, `lammps` and
  # `perf`, and no `omol`.  `doCheck = false` says so rather than leaving a
  # check phase that collects nothing — the silent-zero-tests trap in
  # ../../AGENTS.md.
  doCheck = false;

  # `orca.calc` is the module ../fairchem-core's `recipes/omol.py` reaches for
  # `EVAL_OPT_PARAMETERS`, so it is the one that has to import.  `sella` is
  # optional there and guarded by a `try:`, which this check therefore also
  # covers.
  #
  # `modules.evaluator` has no `__init__.py` beside it — `modules/` is a
  # namespace directory in a distribution that is already two namespace levels
  # deep — so naming it here is the only thing that proves hatchling put it in
  # the wheel.
  pythonImportsCheck = [
    "fairchem.data.omol"
    "fairchem.data.omol.modules.evaluator"
    "fairchem.data.omol.orca.calc"
  ];

  meta = {
    description = "ORCA input generation and evaluation for the OMol25 dataset";
    homepage = "https://github.com/facebookresearch/fairchem";
    changelog = "https://github.com/facebookresearch/fairchem/releases/tag/fairchem_data_omol-${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
