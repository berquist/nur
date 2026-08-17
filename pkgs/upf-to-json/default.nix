{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  numpy,
  scipy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "upf-to-json";
  version = "0.9.5";
  pyproject = true;

  # PEP 625 underscore in the sdist filename; the project is spelled with
  # hyphens.  aiida-core asks for `upf_to_json~=0.9.2` and uv.lock resolves that
  # to 0.9.5.
  src = fetchPypi {
    pname = "upf_to_json";
    inherit version;
    hash = "sha256-V2FMTIZ38E8WFnnOTt2y9VuHmEYFuKUlPT0ogjX1bko=";
  };

  build-system = [ setuptools ];

  dependencies = [
    numpy
    scipy
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "upf_to_json" ];

  meta = {
    description = "Convert pseudopotential files in UPF format to JSON";
    homepage = "https://github.com/simonpintarelli/upf_to_json";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
