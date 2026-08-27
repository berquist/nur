{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  cryptography,
  pyasn1,
  pyasn1-modules,
  python-dateutil,
  requests,
}:

buildPythonPackage rec {
  pname = "rfc3161ng";
  version = "2.1.3";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-HohhTaYbIqvVkVd/ndOdOgMDNfnooS2LwAEUnBfQoB4=";
  };

  build-system = [ setuptools ];

  dependencies = [
    cryptography
    pyasn1
    pyasn1-modules
    python-dateutil
    requests
  ];

  # tests/test_timestamp.py talks to public RFC 3161 timestamping authorities
  # over HTTP and shells out to `openssl ts` to verify the tokens, so it cannot
  # run in a build sandbox.  NOMAD uses this only for the optional
  # trusted-timestamp field on published uploads.
  doCheck = false;

  pythonImportsCheck = [ "rfc3161ng" ];

  meta = {
    description = "RFC 3161 trusted timestamping client";
    homepage = "https://github.com/trbs/rfc3161ng";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.berquist ];
  };
}
