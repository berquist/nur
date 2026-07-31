{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  versioningit,
  qcportal,
  qcengine,
  parsl,
  pydantic,
  pydantic-settings,
  pyyaml,
  numpy,
}:

buildPythonPackage rec {
  pname = "qcfractalcompute";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    # Replace with the real hash:
    #   nix store prefetch-file --json \
    #     "$(nix-instantiate --eval -E \
    #       'with import <nixpkgs> {}; fetchPypi { pname = "qcfractalcompute"; version = "0.65"; }' \
    #       | tr -d '"')"
    # or simply set hash = lib.fakeHash; build once, and paste the error output.
  };

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    qcportal
    qcengine
    parsl
    pydantic
    pydantic-settings
    pyyaml
    numpy
  ];

  pythonImportsCheck = [ "qcfractalcompute" ];

  meta = with lib; {
    description = "QCFractalCompute - compute manager / worker for QCFractal";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
