{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  click,

  # tests
  pytestCheckHook,
}:

# clusterscope — reads CPU, GPU and partition information out of an HPC
# scheduler, so a job can size itself to the node it landed on.  Here for
# ../fairchem-core, which calls `clusterscope.cluster()` and
# `clusterscope.cpus()` from its SLURM launchers.  Internal, not re-exported.
buildPythonPackage (finalAttrs: {
  pname = "clusterscope";
  version = "0.0.18";
  pyproject = true;
  __structuredAttrs = true;

  # Pinned to the version fairchem-core asks for by `==`, rather than to the
  # current v0.0.32, and deliberately: this is a pre-1.0 library whose whole
  # API is one flat namespace re-exported from `clusterscope.lib`, upstream
  # pins it exactly rather than with a floor, and the tag is right there.  That
  # is a cheaper answer than a `pythonRelaxDeps` nobody can justify from
  # reading either side.  It also means fairchem-core is the only thing that
  # ever sees it — see the overlay binding.
  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "clusterscope";
    tag = "v${finalAttrs.version}";
    hash = "sha256-flb1FwRvJNAojaWRl1OhpOAhKzXWJbGM+7hpnX3CQxM=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # setuptools-scm with no repository to read; same pin as ../dargs and
  # ../cmcrameri, and the same failure without it — a wrong version rather than
  # an error.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  dependencies = [ click ];

  nativeCheckInputs = [ pytestCheckHook ];

  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "clusterscope"
    "clusterscope.cli"
  ];

  meta = {
    description = "Extract core information about an HPC cluster from its scheduler";
    homepage = "https://github.com/facebookresearch/clusterscope";
    changelog = "https://github.com/facebookresearch/clusterscope/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "cscope";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
