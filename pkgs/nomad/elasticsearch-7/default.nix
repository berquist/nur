# elasticsearch, pinned to the 7.x client.
#
# nixpkgs ships 8.x.  An 8.x client refuses to talk to a 7.17 server outright
# (it sends a compatibility header the older server rejects, and the response
# body shapes differ), and the Oasis stack runs Elasticsearch 7.17 — that is
# what upstream's docker-compose pins and what nomad-lab declares with
# `elasticsearch-dsl>=7,<8`.  So the pin is on both ends, not just the client.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  certifi,
  urllib3,
}:

buildPythonPackage rec {
  pname = "elasticsearch";
  version = "7.17.13";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-uhuHMiBF/DeDEAnHxJ7w4ndxZaKtM5DfTZ4regnZDIY=";
  };

  build-system = [ setuptools ];

  dependencies = [
    certifi
    urllib3
  ];

  # The sdist ships no tests.  Upstream's live in elasticsearch-py's repo and
  # are almost entirely YAML-driven integration tests that need a running
  # cluster; the client is instead exercised end to end by the oasis-minimal
  # and oasis-upload VM tests, which run a real Elasticsearch 7.17.
  pythonImportsCheck = [ "elasticsearch" ];

  meta = {
    description = "Official low-level Elasticsearch client, 7.x series";
    homepage = "https://github.com/elastic/elasticsearch-py";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
