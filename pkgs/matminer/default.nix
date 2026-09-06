{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  monty,
  numpy,
  pandas,
  pymatgen,
  pymongo,
  requests,
  scikit-learn,
  scipy,
  sympy,
  tqdm,

  # tests
  pytestCheckHook,
  pytest-timeout,
  dscribe,
}:

# matminer — data mining and featurization for materials science.  Carried for
# `matcalc[benchmark]`, and generally useful.  Not re-exported through the
# materials chain's public list on its own account, but it is a real top-level
# tool, so it goes there.
buildPythonPackage (finalAttrs: {
  pname = "matminer";
  version = "0.10.1-unstable-2026-06-30";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "hackingmaterials";
    repo = "matminer";
    rev = "8ddb18c74064ab3668d7b5aed7c360abdfdae5de";
    hash = "sha256-ExrYIMRs93HBUew8+tU2P4mR12fWahj0Qqvun5np+60=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository; the
  # `-unstable-` suffix is not PEP 440.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  build-system = [
    setuptools
    setuptools-scm
  ];

  # `~=` compatible-release pins on requests, tqdm, pymongo, scikit-learn and
  # sympy that the channels here have all moved a minor past.
  pythonRelaxDeps = true;

  dependencies = [
    monty
    numpy
    pandas
    pymatgen
    pymongo
    requests
    scikit-learn
    scipy
    sympy
    tqdm
  ];

  # Only `tests/featurizers` and `tests/utils`.  `tests/data_retrieval` and
  # `tests/datasets` talk to the Materials Project, MPDS, AFLOW, Citrine and MDF
  # APIs, none of which is reachable in a build.  dscribe backs the SOAP/ACSF
  # site featurizers; pytest-timeout because the suite sets per-test timeouts.
  enabledTestPaths = [
    "tests/featurizers"
    "tests/utils"
  ];

  # `OpticalData` / `TransportData` create `~/.matminer/` at construction, and
  # the default /homeless-shelter is not writable; the data itself is bundled.
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # Three failures from dependency drift, not matminer bugs: `test_conversion_
  # multiindex` hits a pandas 3.0 change to how a MultiIndex frame is iterated,
  # `test_min_relative_distances` a pymatgen neighbour-count change, and
  # `test_multitype_multifeat` a base-class edge case behind the same pandas
  # change.  147 pass.
  disabledTests = [
    "test_conversion_multiindex"
    "test_min_relative_distances"
    "test_multitype_multifeat"
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-timeout
    dscribe
  ];

  pythonImportsCheck = [
    "matminer"
    "matminer.featurizers.composition"
    "matminer.featurizers.structure"
  ];

  meta = {
    description = "Data mining and featurization for materials science";
    homepage = "https://github.com/hackingmaterials/matminer";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
