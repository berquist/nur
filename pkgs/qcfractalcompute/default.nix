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
  networkx,
}:

buildPythonPackage rec {
  pname = "qcfractalcompute";
  version = "0.70";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-VHyI38b80HxocjnDTcrvzIODHDHjQwUA7oo+42MBVhE=";
  };

  # run_scripts/qcengine_compute.py runs the QCEngine call under
  # `redirect_stdout(None)`, which sets sys.stdout to None rather than to
  # something writable.  Since QCEngine 0.50.0 that block imports psi4
  # in-process, psi4 imports its endorsed plugins, and adcc reads
  # sys.stdout.isatty() at class-definition time — so every task errors with
  # "'NoneType' object has no attribute 'isatty'".  See the header of the
  # patch, which redirects into StringIO objects instead, as the comment on
  # the line above it already claims it does.
  #
  # The patch adds `import io` as well, and that hunk is not optional: the
  # module imports only json, sys and contextlib, so rewriting the `with` line
  # alone trades the AttributeError for a NameError at the same place, which
  # the server records as the same kind of failed calculation.  The
  # qcfractal-compute-nwchem-singlepoint VM test is what distinguishes them.
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

    # Not a declared dependency of anything: QCEngine's NWChem harness reports
    # itself available only if `which_import("networkx")` succeeds as well as
    # `which("nwchem")` (programs/nwchem/runner.py), and upstream tells you to
    # `conda install networkx` rather than declaring it.  It is listed here
    # because this is the package whose closure becomes the compute module's
    # PYTHONPATH, which is the interpreter that performs discovery — see
    # ../../nixos-modules/qcfractal-compute.nix.  Without it NWChem is silently
    # absent from the programs a worker advertises, indistinguishable from not
    # having installed it.
    networkx
  ];

  pythonImportsCheck = [ "qcfractalcompute" ];

  meta = with lib; {
    description = "QCFractalCompute - compute manager / worker for QCFractal";
    homepage = "https://github.com/MolSSI/QCFractal";
    # The console script is qcfractal-compute-manager, not qcfractalcompute;
    # see the note in ../qcfractal/default.nix.
    mainProgram = "qcfractal-compute-manager";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
