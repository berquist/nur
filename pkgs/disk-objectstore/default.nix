{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  flit-core,

  # dependencies
  click,
  sqlalchemy,

  # tests
  pytestCheckHook,
  psutil,
}:

buildPythonPackage rec {
  pname = "disk-objectstore";
  version = "1.5.0";
  pyproject = true;

  # The sdist is named with an underscore (PEP 625) while the project is
  # spelled with a hyphen, so pname cannot simply be interpolated into the URL.
  src = fetchPypi {
    pname = "disk_objectstore";
    inherit version;
    hash = "sha256-EyeENjDf7FlWxckrFAAedarxLzAU+Y/XHoq4lvFUbi4=";
  };

  build-system = [ flit-core ];

  dependencies = [
    click
    sqlalchemy
  ];

  nativeCheckInputs = [
    pytestCheckHook
    psutil
  ];

  pythonImportsCheck = [
    "disk_objectstore"
    "disk_objectstore.container"
  ];

  meta = {
    description = "An implementation of an efficient object store writing loose objects and packs";
    homepage = "https://github.com/aiidateam/disk-objectstore";
    license = lib.licenses.mit;
    mainProgram = "dostore";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
