{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  appdirs,
  ase,
  click,
  psutil,
  pydantic,
  pydantic-settings,
  requests,
  tqdm,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "molid";
  version = "0.8.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-L2naZL1+D4hNBkD3Ixwp7Z69H/89VlRj45vYfFMTFl8=";
  };

  build-system = [ setuptools ];

  dependencies = [
    appdirs
    ase
    click
    psutil
    pydantic
    pydantic-settings
    requests
    tqdm
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # The whole suite runs offline: the only test that touches PubChem replaces
  # pubchem_client.get_session with a stub via monkeypatch.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [ "molid" ];

  meta = {
    description = "Molecule identification and PubChem lookup used by NOMAD's chemical normalizer";
    homepage = "https://pypi.org/project/molid/";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
