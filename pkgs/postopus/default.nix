{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  ase,
  attrs,
  h5py,
  netcdf4,
  numpy,
  pandas,
  psutil,
  pyvista,
  vtk,
  xarray,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "postopus";
  version = "0.5.0";
  pyproject = true;

  # aiida-octopus pins `postopus>=0.5.0,<0.6`, so this is the series it wants.
  # The dependency list above was reconstructed from the package metadata rather
  # than from a resolved environment, so it is the most likely thing here to
  # need adjusting when postopus itself changes.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-y1jd+thlTMg1GvxtxqwY74aRt9QEHEPWBprQ/7p3l24=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  dependencies = [
    ase
    attrs
    h5py
    netcdf4
    numpy
    pandas
    psutil
    pyvista
    vtk
    xarray
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "postopus" ];

  meta = {
    description = "Post-processing library for Octopus output";
    homepage = "https://gitlab.com/octopus-code/postopus";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
