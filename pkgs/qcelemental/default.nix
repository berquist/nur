{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  poetry-core,
  setuptools,
  setuptools-scm,

  # dependencies
  numpy,
  packaging,
  pint,
  pydantic,

  # optional-dependencies
  ipykernel,
  networkx,
  scipy,

  # tests
  pytestCheckHook,
}:

# A backport, not a package of ours.  ../qcportal declares
# `qcelemental>=0.50.2,<0.70a0`, and nixos-26.05 carries 0.50.0rc3.  That is a
# hard floor rather than a pin to relax: pythonRuntimeDepsCheckHook fails the
# wheel after it has been built --
#
#     Checking runtime dependencies for qcportal-0.70-py3-none-any.whl
#       - qcelemental<0.70a0,>=0.50.2 not satisfied by version 0.50.0rc3
#
# -- and qcportal/qcschema_v1.py imports fifteen names from
# `qcelemental.models._v1v2`, a *private* module that is what the floor is
# about.  Relaxing it, or setting `dontCheckRuntimeDeps`, would trade a build
# failure for an ImportError at run time.
#
# There can only be one qcelemental in a package set -- the import path is
# `qcelemental` either way -- so this is a plain member of the qcfractal
# extension rather than the `let`-bound, threaded-in shape ../../overlays
# uses for pymatgenFor.  That pattern keeps an override invisible to the rest
# of a consumer's package set, and it does not work for a name every consumer
# already has.
#
# The binding in ../../overlays/default.nix is guarded, so a channel already
# carrying 0.50.2 or newer keeps its own and this file goes unused on that leg.
# **Delete it once every leg of ../../Justfile's `channels` is past that
# version**, and drop the binding with it.
#
# Kept deliberately close to nixpkgs'
# pkgs/development/python-modules/qcelemental at 0.50.4 rather than restyled,
# so the two can be diffed and so deleting this is the obvious move.  Two
# deviations: the unused `stdenv` and `pythonAtLeast` arguments are dropped so
# deadnix passes, and with `stdenv` goes 26.05's `meta.broken =
# stdenv.hostPlatform.isDarwin`, which nixpkgs itself dropped by this version.
buildPythonPackage rec {
  pname = "qcelemental";
  version = "0.50.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-jVOCbTP/FXyqL1yJbBkxHPPJ2vcZyrjG+GBg+V1fdEs=";
  };

  build-system = [
    poetry-core
    setuptools
    setuptools-scm
  ];

  dependencies = [
    numpy
    packaging
    pint
    pydantic
  ];

  optional-dependencies = {
    viz = [
      # TODO: nglview
      ipykernel
    ];
    align = [
      networkx
      scipy
    ];
  };

  nativeCheckInputs = [ pytestCheckHook ] ++ lib.concatAttrValues optional-dependencies;

  pythonImportsCheck = [ "qcelemental" ];

  # These tests require network access
  disabledTestPaths = [
    "qcelemental/tests/test_gph_uno_bipartite.py"
    "qcelemental/tests/test_model_general.py"
    "qcelemental/tests/test_model_results.py"
    "qcelemental/tests/test_molecule.py"
    "qcelemental/tests/test_molparse_align_chiral.py"
    "qcelemental/tests/test_molparse_from_schema.py"
    "qcelemental/tests/test_molparse_from_string.py"
    "qcelemental/tests/test_molparse_pubchem.py"
    "qcelemental/tests/test_molparse_to_schema.py"
    "qcelemental/tests/test_molparse_to_string.py"
    "qcelemental/tests/test_molutil.py"
    "qcelemental/tests/test_utils.py"
    "qcelemental/tests/test_zqcschema.py"
  ];

  # `report` rather than the inferred `stable`.  This file exists to sit inside
  # ../qcportal's version window, and that window has a ceiling as well as a
  # floor: an unattended bump past `<0.70a0` would break the package the
  # backport is here to serve.  Bumps within the window are worth knowing about
  # and are not worth a bot doing on its own, since the whole file is meant to
  # be deleted rather than maintained.
  passthru.updatePolicy = {
    mode = "report";
    reason = "a backport pinned inside qcportal's >=0.50.2,<0.70a0 window; delete rather than bump once 26.05 leaves the matrix";
  };

  meta = {
    description = "Periodic table, physical constants and molecule parsing for quantum chemistry";
    homepage = "https://github.com/MolSSI/QCElemental";
    changelog = "https://github.com/MolSSI/QCElemental/blob/v${version}/docs/changelog.rst";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
