{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  deepmerge,
  pyyaml,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "configurables";
  version = "1.2.2";
  pyproject = true;

  # HEAD is exactly the v1.2.2 tag, so this is a release build despite coming
  # from git — the project has never been published to PyPI.
  src = fetchFromGitHub {
    owner = "Digichem-Project";
    repo = "configurables";
    rev = "v${version}";
    hash = "sha256-VulgXRffUXY+GMNvKuXmq/Fy9O5AS5oWGSxbKlxVwAw=";
  };

  build-system = [ hatchling ];

  dependencies = [
    deepmerge
    pyyaml
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "configurables"
    "configurables.option"
    "configurables.parent"
  ];

  meta = {
    description = "Validation for object attributes and dynamic loading of objects from config files";
    homepage = "https://github.com/Digichem-Project/configurables";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
