{
  lib,
  buildPythonPackage,
  pythonAtLeast,
  fetchPypi,
  setuptools,
  versioningit,
  numpy,
  msgpack,
  requests,
  pyyaml,
  pydantic,
  pydantic-settings,
  zstandard,
  apsw,
  qcelemental,
  tabulate,
  tqdm,
  pandas,
  pyjwt,
  dateutils,
  pytz,
}:

buildPythonPackage rec {
  pname = "qcportal";
  version = "0.65";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-fgY2i9HhLpUhsnK5nX6ovMVTj6QRKPTZtDVQv9OLoKw=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    numpy
    msgpack
    requests
    pyyaml
    pydantic
    pydantic-settings
    zstandard
    apsw
    qcelemental
    tabulate
    tqdm
    pandas
    pyjwt
    dateutils
    pytz
  ];

  pythonImportsCheck = [ "qcportal" ];

  meta = with lib; {
    # qcportal 0.65 is built on pydantic v1 throughout, and qcelemental refuses
    # to provide QCSchema v1 on Python 3.14+: _use_real_if_possible() in
    # qcelemental/models/v1/__init__.py returns False for sys.version_info >=
    # (3, 14), replacing every v1 name with a placeholder class.  One of those
    # names is Array, which dataset_models.py subscripts as
    #
    #   index: Array[str]
    #
    # The placeholder has an ordinary metaclass, so pydantic v1 resolving that
    # annotation dies with "TypeError: type 'Array' is not subscriptable" and
    # pythonImportsCheck turns it into a build failure.  Nothing here can patch
    # around it, and there is no release to move to: 0.65 is the newest, and
    # upstream's pydantic v2 migration is unreleased.  Drop this (and the
    # python313 pin in ../../default.nix) once that lands.
    broken = pythonAtLeast "3.14";
    description = "Python client for QCFractal / QCArchive servers";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
