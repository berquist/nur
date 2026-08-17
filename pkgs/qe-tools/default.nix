{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  flit-core,

  # dependencies
  numpy,
  packaging,
  xmlschema,

  # tests
  pytestCheckHook,
  pytest-regressions,
}:

buildPythonPackage rec {
  pname = "qe-tools";
  version = "2.3.0";
  pyproject = true;

  # aiida-quantumespresso asks for `qe-tools~=2.0`, i.e. anything in the 2.x
  # series.  PEP 625 underscore in the sdist name, hence the explicit pname.
  src = fetchPypi {
    pname = "qe_tools";
    inherit version;
    hash = "sha256-AL/JM6TlIeT82kZgD/+2VETDTUzV5MCgnk0prjbkvbw=";
  };

  build-system = [ flit-core ];

  dependencies = [
    numpy
    packaging
    xmlschema
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions
  ];

  pythonImportsCheck = [ "qe_tools" ];

  meta = {
    description = "Tools for the Quantum ESPRESSO input and output formats";
    homepage = "https://github.com/aiidateam/qe-tools";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
