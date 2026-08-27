{
  lib,
  buildPythonPackage,
  fetchPypi,
  poetry-core,
  pydantic,
}:

buildPythonPackage rec {
  pname = "lazy-model";
  version = "0.4.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-qFHYXQtRiwucjmJrvuD+sElMDgy1Y2VQY38DLbv5xV8=";
  };

  build-system = [ poetry-core ];

  dependencies = [ pydantic ];

  # The sdist ships no tests, and upstream tags no releases on GitHub, so there
  # is nothing to run beyond the import.
  pythonImportsCheck = [ "lazy_model" ];

  meta = {
    description = "Pydantic models with lazy field parsing, used by beanie";
    homepage = "https://github.com/roman-right/lazy-model";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
