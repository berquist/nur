# opentelemetry-instrumentation-elasticsearch.
#
# Same story as the pymongo sibling: nomad-lab pins ==0.63b1, nixpkgs never
# carried it, so this follows nixpkgs' 0.64b0 and nomad-lab relaxes the pin.
# See ../opentelemetry-instrumentation-pymongo/default.nix for the full
# reasoning and ../nomad-lab/default.nix for the relaxation.
{
  lib,
  buildPythonPackage,
  hatchling,
  opentelemetry-api,
  opentelemetry-instrumentation,
  opentelemetry-semantic-conventions,
  wrapt,
  elasticsearch,
  # tests
  elasticsearch-dsl,
  opentelemetry-test-utils,
  pytestCheckHook,
}:

buildPythonPackage {
  inherit (opentelemetry-instrumentation) version src;
  pname = "opentelemetry-instrumentation-elasticsearch";
  pyproject = true;

  sourceRoot = "${opentelemetry-instrumentation.src.name}/instrumentation/opentelemetry-instrumentation-elasticsearch";

  build-system = [ hatchling ];

  dependencies = [
    opentelemetry-api
    opentelemetry-instrumentation
    opentelemetry-semantic-conventions
    wrapt
  ];

  optional-dependencies = {
    instruments = [ elasticsearch ];
  };

  # elasticsearch-dsl is a check input and not a dependency: the package itself
  # instruments the bare elasticsearch client, but tests/test_elasticsearch.py
  # does `from elasticsearch_dsl import Search` at module scope to check that a
  # DSL-built query still produces one span.  Without it the whole module fails
  # at collection with ModuleNotFoundError.  Listing a check-only dependency
  # here is what nixpkgs' own contrib packages do — see the redis, celery and
  # django instrumentations, each of which pulls its instrumented library in as
  # a nativeCheckInput and nothing more.
  nativeCheckInputs = [
    opentelemetry-test-utils
    pytestCheckHook
    elasticsearch
    elasticsearch-dsl
  ];

  # The suite patches elasticsearch's transport and asserts on the emitted
  # spans, so it needs no cluster.  It does branch on `elasticsearch.VERSION`,
  # and the `elasticsearch` in scope here is our 7.17 pin rather than nixpkgs'
  # 8.x — that gating turns out to be fine, but it is where to look first if
  # this package ever fails again.
  pythonImportsCheck = [ "opentelemetry.instrumentation.elasticsearch" ];

  meta = opentelemetry-instrumentation.meta // {
    homepage = "https://github.com/open-telemetry/opentelemetry-python-contrib/tree/main/instrumentation/opentelemetry-instrumentation-elasticsearch";
    description = "Elasticsearch instrumentation for OpenTelemetry";
    maintainers = [ lib.maintainers.berquist ];
  };
}
