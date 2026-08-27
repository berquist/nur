# elasticsearch-dsl, pinned to the 7.x line.
#
# nixpkgs ships 8.18.0, and nomad-lab declares `elasticsearch-dsl>=7,<8`.  The
# 8.x rewrite renamed enough of the query DSL surface that NOMAD's search layer
# — which is built directly on this API — will not run against it.  Unlike the
# other pins here there is no older nixpkgs revision to take the expression
# from: every branch that carried a 7.x elasticsearch-dsl carried 7.4.0 at
# newest, in python2-era expressions that no longer callPackage cleanly.
#
# Source is GitHub rather than PyPI because the sdist ships no tests at all,
# and this is the one downgrade with no fallback — its own suite is the
# early-warning system for 2023-era code on Python 3.13.
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  elasticsearch,
  python-dateutil,
  six,
  # tests
  pytestCheckHook,
  mock,
  pytest-mock,
  pytz,
}:

buildPythonPackage rec {
  pname = "elasticsearch-dsl";
  version = "7.4.1";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "elastic";
    repo = "elasticsearch-dsl-py";
    tag = "v${version}";
    hash = "sha256-6AYvrUP3ncTw7rDcUSA+lkGPFhnXEBU2lB0KV9LvZGA=";
  };

  build-system = [ setuptools ];

  dependencies = [
    elasticsearch
    python-dateutil
    six
  ];

  nativeCheckInputs = [
    pytestCheckHook
    mock
    pytest-mock
    pytz
  ];

  # tests/test_integration/ needs a live cluster (its conftest builds an
  # Elasticsearch client and indexes fixture documents); everything else is
  # pure unit tests over the query DSL and runs offline.  The integration half
  # is covered instead by the oasis-minimal and oasis-upload VM tests, which
  # run a real Elasticsearch 7.17.
  enabledTestPaths = [ "tests" ];
  disabledTestPaths = [ "tests/test_integration" ];

  pythonImportsCheck = [
    "elasticsearch_dsl"
    "elasticsearch_dsl.query"
  ];

  meta = {
    description = "High-level client for Elasticsearch, 7.x series";
    homepage = "https://github.com/elastic/elasticsearch-dsl-py";
    changelog = "https://github.com/elastic/elasticsearch-dsl-py/blob/${src.tag}/Changelog.rst";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.berquist ];
  };
}
