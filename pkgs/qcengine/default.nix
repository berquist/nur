{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  pyyaml,
  py-cpuinfo,
  psutil,
  qcelemental,
  pydantic,
  pydantic-settings,
  packaging,

  # tests
  pytestCheckHook,
}:

# A backport, not a package of ours, and the sibling of ../qcelemental.
# ../qcfractalcompute and ../qcarchivetesting both declare
# `qcengine>=0.50,<0.70a0`, and nixos-26.05 carries 0.50.0rc2 --
#
#     Checking runtime dependencies for qcfractalcompute-0.70-py3-none-any.whl
#       - qcengine<0.70a0,>=0.50 not satisfied by version 0.50.0rc2
#
# -- a release *candidate*, which under PEP 440 precedes 0.50 and so does not
# meet the floor.  That is what makes this one more dangerous than ../qcelemental
# rather than merely another instance of it: nix's `versionAtLeast` does not
# know PEP 440 and reads "0.50.0rc2" as *newer* than "0.50".  See the
# `newEnough` binding in ../../overlays/default.nix, which is where the guard
# has to say so.
#
# There can only be one qcengine in a package set, so this is a plain member of
# the qcfractal extension.  The binding there is guarded, so a channel already
# carrying a real 0.50 or newer keeps its own and this file goes unused on that
# leg.  **Delete it once every leg of ../../Justfile's `channels` is past that
# version**, and drop the binding with it.
#
# Kept deliberately close to nixpkgs'
# pkgs/development/python-modules/qcengine at 0.50.0 rather than restyled, so
# the two can be diffed and so deleting this is the obvious move.  `homepage`
# points at QCElemental's documentation rather than QCEngine's, which is
# nixpkgs' error and is carried over unchanged rather than guessed at here.
buildPythonPackage rec {
  pname = "qcengine";
  version = "0.50.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-x218Sq4QOoqTpcSM9TzQydhIn9LthflCuNh/P0stZmU=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    pyyaml
    py-cpuinfo
    psutil
    qcelemental
    pydantic
    pydantic-settings
    packaging
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "qcengine" ];

  # These tests require network access
  disabledTestPaths = [
    "qcengine/tests/test_harness_canonical.py"
  ];

  # `report` rather than the inferred `stable`, for ../qcelemental's reason:
  # this file exists to sit inside a version window with a ceiling as well as a
  # floor, and is meant to be deleted rather than maintained.
  passthru.updatePolicy = {
    mode = "report";
    reason = "a backport pinned inside qcfractalcompute's >=0.50,<0.70a0 window; delete rather than bump once 26.05 leaves the matrix";
  };

  meta = {
    description = "Quantum chemistry program executor and IO standardizer (QCSchema) for quantum chemistry";
    homepage = "https://molssi.github.io/QCElemental/";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
    mainProgram = "qcengine";
  };
}
