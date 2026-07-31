# pkgs/qcfractalcompute.nix
#
# qcfractalcompute - the QCFractalCompute worker / manager.
# Provides the `qcfractal-compute-manager` CLI entry point.
#
# Dependencies (from the live config.py source and qcfractalcompute pyproject):
#
#   qcportal (same version)   - REST client used to claim/return tasks
#   qcengine                   - execution backend (calls QC programs)
#   parsl                      - parallel task execution framework
#   pydantic >=2
#   pydantic-settings
#   PyYAML
#   numpy
#
# Note on pydantic compatibility: the live config.py source shows:
#   try:
#       from pydantic.v1 import BaseModel, …
#   except ImportError:
#       from pydantic import BaseModel, …
# This means qcfractalcompute works with both pydantic v1 and v2.
# Since we're using pydantic v2 (in nixpkgs), the `pydantic.v1` shim path
# is taken automatically - no extra package is needed.

{
  buildPythonPackage,
  fetchPypi,
  lib,
  qcportal, # our local package
  qcengine, # already in nixpkgs
  parsl, # already in nixpkgs
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
  };

  # propagatedBuildInputs = [
  #   qcportal
  #   qcengine
  #   parsl
  #   pydantic
  #   pydantic-settings
  #   pyyaml
  #   numpy
  # ];

  # dontBuild = true;

  pythonImportsCheck = [ "qcfractalcompute" ];

  meta = with lib; {
    description = "QCFractalCompute - compute manager / worker for QCFractal";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
