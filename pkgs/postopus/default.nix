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

  # Octopus itself, which the suite runs to generate the output trees it then
  # reads back — tests/utils/octopus_runner.py shells out to `octopus`.  It is
  # not a runtime dependency: postopus post-processes files that already exist.
  #
  # Defaulted because no single spelling resolves everywhere: nixpkgs has it at
  # the top level, NixOS-QChem replaces it as `qchem.octopus`, and overlays/ is
  # imported without flakes by default.nix, overlay.nix and ci.nix, so it cannot
  # reach that input — the same constraint that makes cclib a flake-only
  # dependency here.  ../../overlays/default.nix picks whichever spelling the
  # package set has, and builds it without MPI so it can run in a sandbox; this
  # falls back to running fewer tests when there is none.
  octopus ? null,
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

  nativeCheckInputs = [
    pytestCheckHook
  ]
  ++ lib.optional (octopus != null) octopus;

  # Without octopus on PATH the generating fixture aborts and every test
  # downstream of it errors with "No such file or directory: 'octopus'" — 89 of
  # the 139 collected.  Skip exactly those, so the package still builds on a
  # set that has no Octopus while running the whole suite on the one that does.
  #
  # Listed per file rather than per directory because test_files/test_xyz_read.py
  # and four of the seven test_output_collector files need no calculation.
  disabledTestPaths = lib.optionals (octopus == null) [
    "tests/test_files/test_cube_read.py"
    "tests/test_files/test_netcdf_read.py"
    "tests/test_files/test_pandastext_read.py"
    "tests/test_files/test_text_read.py"
    "tests/test_files/test_value_crosschecks.py"
    "tests/test_files/test_vtk_read.py"
    "tests/test_files/test_xcrysden_read.py"
    "tests/test_interface"
    "tests/test_octopus_inp_parser"
    "tests/test_output_collector/test_blacklisting.py"
    "tests/test_output_collector/test_integration.py"
    "tests/test_output_collector/test_other_index.py"
  ];

  pythonImportsCheck = [ "postopus" ];

  meta = {
    description = "Post-processing library for Octopus output";
    homepage = "https://gitlab.com/octopus-code/postopus";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
