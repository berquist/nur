{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  deprecation,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "pytray";
  version = "0.3.4";
  pyproject = true;

  # Pulled in only by kiwipy's `rmq` extra, which aiida-core requires.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-VfmoWNpPTrmxf1+M062ETw2NRafJMulAvCjE7x2knLw=";
  };

  build-system = [ setuptools ];

  dependencies = [ deprecation ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "pytray" ];

  meta = {
    description = "A python tray of util functions";
    homepage = "https://github.com/muhrin/pytray";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
