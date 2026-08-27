# opentelemetry-instrumentation-pymongo.
#
# nomad-lab pins this at ==0.63b1, but nixpkgs went 0.61b0 -> 0.64b0 and never
# carried 0.63b1, so there is no revision to take the expression from.  Rather
# than downgrade the whole lockstep-versioned opentelemetry family by hand,
# this follows nixpkgs' 0.64b0 and nomad-lab relaxes the pin (see
# pythonRelaxDeps in ../nomad-lab/default.nix for why that is safe: NOMAD calls
# only PymongoInstrumentor().instrument()).
#
# Built exactly the way nixpkgs builds its own contrib packages — inheriting
# version and src from opentelemetry-instrumentation and pointing sourceRoot
# into the monorepo — so it needs no hash of its own and cannot drift out of
# lockstep with the rest of the family.
{
  lib,
  buildPythonPackage,
  hatchling,
  opentelemetry-api,
  opentelemetry-instrumentation,
  opentelemetry-semantic-conventions,
  pymongo,
  # tests
  opentelemetry-test-utils,
  pytestCheckHook,
}:

buildPythonPackage {
  inherit (opentelemetry-instrumentation) version src;
  pname = "opentelemetry-instrumentation-pymongo";
  pyproject = true;

  sourceRoot = "${opentelemetry-instrumentation.src.name}/instrumentation/opentelemetry-instrumentation-pymongo";

  build-system = [ hatchling ];

  dependencies = [
    opentelemetry-api
    opentelemetry-instrumentation
    opentelemetry-semantic-conventions
  ];

  optional-dependencies = {
    instruments = [ pymongo ];
  };

  nativeCheckInputs = [
    opentelemetry-test-utils
    pytestCheckHook
    pymongo
  ];

  # The suite drives a MockCommand/MockConnection through the instrumented
  # CommandListener rather than a live mongod, so it runs offline.
  pythonImportsCheck = [ "opentelemetry.instrumentation.pymongo" ];

  meta = opentelemetry-instrumentation.meta // {
    homepage = "https://github.com/open-telemetry/opentelemetry-python-contrib/tree/main/instrumentation/opentelemetry-instrumentation-pymongo";
    description = "PyMongo instrumentation for OpenTelemetry";
    maintainers = [ lib.maintainers.berquist ];
  };
}
