{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  poetry-core,

  # dependencies
  regex,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "cp2k-output-tools";
  version = "0.5.0";
  pyproject = true;

  # aiida-cp2k depends on this unbounded, so any recent release will do.
  # PEP 625 underscore in the sdist name, hence the explicit pname.
  src = fetchPypi {
    pname = "cp2k_output_tools";
    inherit version;
    hash = "sha256-xxeGpuDpnx1wbuo1WXe8XWdxtAy32Er8eSHunV6aBCA=";
  };

  build-system = [ poetry-core ];

  dependencies = [ regex ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "cp2k_output_tools" ];

  meta = {
    description = "Parsers and tools for CP2K output files";
    homepage = "https://github.com/cp2k/cp2k-output-tools";
    license = lib.licenses.mit;
    mainProgram = "cp2k-output-tools";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
