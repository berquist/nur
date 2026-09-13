{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  pathos,
  six,
  tqdm,

  # tests
  pytestCheckHook,
}:

# p-tqdm — `map` over a process or thread pool with a tqdm progress bar on top.
# A thin wrapper: pathos does the parallelism, tqdm does the bar.
#
# Here for `fairchem-applications-fastcsp`, which is one of the two remaining
# fairchem distributions with a gap in nixpkgs, and for nothing else.  See
# "Deferred packaging" in ../../AGENTS.md.  Internal, not re-exported.
#
# Distribution `p_tqdm`, import `p_tqdm`; the attribute is spelled with a dash,
# which is what nixpkgs does with an underscore in a distribution name.
buildPythonPackage (finalAttrs: {
  pname = "p-tqdm";
  version = "1.4.2";
  pyproject = true;
  __structuredAttrs = true;

  # The tag carries an underscore — `v_1.4.2`, not `v1.4.2` — which is
  # upstream's own habit and matches the `download_url` its setup.py builds.
  src = fetchFromGitHub {
    owner = "swansonk14";
    repo = "p_tqdm";
    tag = "v_${finalAttrs.version}";
    hash = "sha256-J1ec93QtwPMP3shsHeM3YSC1HHulmqCi/7t+fls5YZk=";
  };

  build-system = [ setuptools ];

  # Upstream's whole `install_requires`.  `six` is there for pathos' sake rather
  # than p_tqdm's own — nothing in the package imports it — but it is declared,
  # and `pythonRuntimeDepsCheckHook` reads declarations.
  dependencies = [
    pathos
    six
    tqdm
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [ "p_tqdm" ];

  meta = {
    description = "Parallel processing with progress bars";
    homepage = "https://github.com/swansonk14/p_tqdm";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
