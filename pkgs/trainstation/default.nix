{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,

  # dependencies
  numpy,
  scikit-learn,
  scipy,

  # tests
  pytestCheckHook,
}:

# trainstation — linear-model fitting with cross-validation, from the same group
# as hiPhive and for hiPhive's benefit alone: it is the one requirement of
# ../hiphive that nixpkgs does not carry, and hiPhive is in turn `shakenbreak`'s.
# Internal, not re-exported — see "Deferred packaging" in ../../AGENTS.md.
buildPythonPackage {
  pname = "trainstation";
  version = "1.2-unstable-2025-07-30";
  pyproject = true;
  __structuredAttrs = true;

  # GitLab, like ../hiphive and ../aiida-octopus.  HEAD rather than the `1.2`
  # tag, four commits past it and all of them repository housekeeping; the
  # version attribute upstream reads is still `1.2`.
  src = fetchFromGitLab {
    owner = "materials-modeling";
    repo = "trainstation";
    rev = "7b55bfc26c3764b4c9c28b35886d88c156358f08";
    hash = "sha256-vzpHJTT4vnRMXdszVAcfSRw0DHJ+7hapimiUwzBkStE=";
  };

  build-system = [ setuptools ];

  dependencies = [
    numpy
    scikit-learn
    scipy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # Eight modules of plain `unittest` cases needing nothing beyond numpy, named
  # explicitly so a glob matching nothing stays fatal.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "trainstation"
  ];

  meta = {
    description = "Convenient training of linear models";
    homepage = "https://gitlab.com/materials-modeling/trainstation";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
