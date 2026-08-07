{
  lib,
  buildPythonPackage,
  pythonAtLeast,
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
  # pytestCheckHook,
  # qcarchivetesting,
}:

buildPythonPackage rec {
  pname = "qcfractalcompute";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-QxAvT7GEBogE8LQa5nIp6//p37qvOX3aTfjOJVVxu/I=";
  };

  # run_scripts/qcengine_compute.py runs the QCEngine call under
  # `redirect_stdout(None)`, which sets sys.stdout to None rather than to
  # something writable.  Since QCEngine 0.50.0 that block imports psi4
  # in-process, psi4 imports its endorsed plugins, and adcc reads
  # sys.stdout.isatty() at class-definition time — so every task errors with
  # "'NoneType' object has no attribute 'isatty'".  See the header of the
  # patch, which redirects into StringIO objects instead, as the comment on
  # the line above it already claims it does.
  patches = [ ./qcengine-compute-stdout.patch ];

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

  # nativeCheckInputs = [
  #   pytestCheckHook
  #   qcarchivetesting
  # ];

  pythonImportsCheck = [ "qcfractalcompute" ];

  meta = with lib; {
    # Inherited from qcportal; see the note in ../qcportal/default.nix.
    broken = pythonAtLeast "3.14";
    description = "QCFractalCompute - compute manager / worker for QCFractal";
    homepage = "https://github.com/MolSSI/QCFractal";
    # The console script is qcfractal-compute-manager, not qcfractalcompute;
    # see the note in ../qcfractal/default.nix.
    mainProgram = "qcfractal-compute-manager";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
