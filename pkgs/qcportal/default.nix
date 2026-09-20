{
  lib,
  buildPythonPackage,
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
  packaging,
  python-dateutil,
}:

buildPythonPackage rec {
  pname = "qcportal";
  version = "0.70";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-sps7Ssi22WFZXHSBDhieBjb40efEqGfPMx7XxlUnhM4=";
  };

  build-system = [
    setuptools
    versioningit
  ];

  # 0.70 moved four of these: `dateutils` became `python-dateutil` — a different
  # distribution, not a rename of the same one — `pytz` was dropped, and
  # `packaging` added.  The old list kept importing anyway, because pandas pulls
  # both of the right ones in transitively, so nothing failed to say so.
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
    packaging
    python-dateutil
  ];

  pythonImportsCheck = [ "qcportal" ];

  # No interpreter gate, and that is the whole reason ../../default.nix follows
  # the channel's default python3 rather than pinning 3.13.  Until 0.70 this
  # carried `broken = pythonAtLeast "3.14"`: 0.65 was pydantic v1 throughout,
  # and qcelemental replaces every QCSchema v1 name with a placeholder class on
  # 3.14 (see _make_placeholder in qcelemental/models/v1/__init__.py), one of
  # which is the `Array` that dataset_models.py subscripts as `index: Array[str]`.
  # 0.70 asks for pydantic>=2.11, declares requires-python = ">=3.10" with no
  # ceiling, and reaches qcelemental.models._v1v2 rather than the v1 shim, so
  # the mechanism cannot fire.  ../aiida-psi4 is the one package here that still
  # instantiates a v1 model, and carries the marking on its own account.
  meta = with lib; {
    description = "Python client for QCFractal / QCArchive servers";
    homepage = "https://github.com/MolSSI/QCFractal";
    license = lib.licenses.bsd3;
    maintainers = with maintainers; [ berquist ];
  };
}
