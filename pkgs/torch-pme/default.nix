{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  torch,

  # tests
  pytestCheckHook,
  ase,
  scipy,
  vesin,
}:

# torch-pme — particle-mesh Ewald and related long-range electrostatics in
# PyTorch, from the same group as `vesin` and `metatensor`.  Dist `torch-pme`,
# import `torchpme`.
#
# Here for ../nvalchemi-toolkit-ops, whose electrostatics suite validates its own
# Ewald and PME kernels against this as an independent reference.  Four of its
# modules guard on `HAS_TORCHPME`, and what they skip without it is the entire
# correctness half of that suite — so this is a check input that buys real
# coverage rather than a box ticked.  Internal, not re-exported.
buildPythonPackage (finalAttrs: {
  pname = "torch-pme";
  version = "0.5.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "lab-cosmo";
    repo = "torch-pme";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lPmqrHIUi6EUW8spZqyNLKDX0CAsWo5b7mwCSSwc7mk=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # Pinned rather than left to setuptools-scm, whose failure here is a wrong
  # version rather than an error — the same reason ../dargs and ../clusterscope
  # pin it.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # Upstream's whole `dependencies` list.  Its two extras are left out: the
  # `examples` one wants chemiscope and vesin, and `metatensor` wants
  # metatensor-torch and metatomic-torch, none of which nixpkgs carries.
  dependencies = [ torch ];

  # ase because `tests/calculators/test_padding.py` and three others read the
  # reference structures with `ase.io.read` at module scope, and vesin because
  # `tests/helpers.py` builds its neighbour lists with it — and upstream's
  # `python_files = ["*.py"]` makes `helpers.py` itself a collected module, so
  # without vesin the run dies at collection rather than skipping eight
  # modules.  ../vesin is this repository's own package.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    scipy
    vesin
  ];

  # Upstream's `addopts` carries `--cov --cov-append --cov-report=`, which needs
  # pytest-cov and writes coverage output that is thrown away here.  Without
  # either the plugin or this, pytest rejects the whole invocation with
  # "unrecognized arguments" before collecting anything — the same fix, for the
  # same reason, as ../disk-objectstore and ../aiida-core.
  pytestFlags = [ "--override-ini=addopts=" ];

  enabledTestPaths = [ "tests" ];

  # Eighteen of the twenty modules run.  The two here want `metatensor-torch`
  # and `metatomic-torch`, which nixpkgs does not carry and nothing else in this
  # repository needs; they are upstream's `metatensor` extra, and they test an
  # interface layer rather than any of the arithmetic that the other eighteen
  # cover.
  disabledTestPaths = [ "tests/metatensor" ];

  # `torchpme.metatensor` is left out: it imports metatensor-torch at module
  # scope, which is neither a dependency here nor in nixpkgs.
  pythonImportsCheck = [
    "torchpme"
    "torchpme.calculators"
    "torchpme.lib"
    "torchpme.lib.kvectors"
    "torchpme.potentials"
    "torchpme.tuning"
  ];

  meta = {
    description = "Particle-mesh based calculations of long-range interactions in PyTorch";
    homepage = "https://github.com/lab-cosmo/torch-pme";
    changelog = "https://lab-cosmo.github.io/torch-pme/latest/references/changelog.html";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
