# nomad-lab — the NOMAD Oasis application itself.
#
# Built from the **PyPI sdist**, not from a git checkout, and that is the single
# most load-bearing decision in this package.  nomad's Dockerfile builds the
# React GUI with yarn and copies it to nomad/app/static/gui *before* `uv build`,
# and MANIFEST.in grafts that directory — so the sdist already contains the
# built GUI (337 files under nomad/app/static/gui).  `nomad admin run app
# --with-gui` only copies that tree into the working directory and rewrites the
# base path in it (nomad/cli/admin/run.py:203).  Building from
# FAIRmat-NFDI/nomad instead would mean reproducing an offline yarn /
# react-scripts-4 build, which is a project in itself.
#
# setuptools-scm needs no SETUPTOOLS_SCM_PRETEND_VERSION here for the same
# reason: the sdist carries PKG-INFO, which is setuptools-scm's documented
# fallback when there is no .git.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  py-spy,

  # base dependencies, in pyproject.toml order
  ase,
  bitarray,
  cachetools,
  click,
  docstring-parser,
  elasticsearch,
  elasticsearch-dsl,
  fsspec,
  h5py,
  httpx,
  jmespath,
  jsonpath-ng,
  json-stream,
  kaleido,
  lxml,
  matid,
  molid,
  msglc,
  numpy,
  openpyxl,
  orjson,
  pandas,
  pathvalidate,
  pint,
  plotly,
  pydantic,
  pyinstrument,
  pymatgen,
  python-keycloak,
  python-magic,
  pyyaml,
  requests,
  rfc3161ng,
  scipy,
  unidecode,
  xarray,

  # the [infrastructure] extra — unconditional here, because the NixOS module
  # always runs the app and the worker, never the bare parsing library
  beautifulsoup4,
  beanie,
  blinker,
  cryptography,
  fastapi,
  fastapi-cache2,
  gunicorn,
  h5grove,
  mongoengine,
  optimade,
  prometheus-client,
  pyjwt,
  python-logstash,
  python-multipart,
  rdflib,
  starlette,
  structlog,
  tabulate,
  temporalio,
  uvicorn,
  validators,
  zipstream-ng,
  opentelemetry-api,
  opentelemetry-sdk,
  opentelemetry-exporter-otlp,
  opentelemetry-exporter-otlp-proto-grpc,
  opentelemetry-instrumentation-asgi,
  opentelemetry-instrumentation-fastapi,
  opentelemetry-instrumentation-pymongo,
  opentelemetry-instrumentation-elasticsearch,
}:

buildPythonPackage rec {
  pname = "nomad-lab";
  version = "1.4.3";
  pyproject = true;

  src = fetchPypi {
    pname = "nomad_lab";
    inherit version;
    hash = "sha256-2Vx15LQwgPEYueKeyfZBcBxsyzlafUMaFikkVpkNFoc=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  pythonRelaxDeps = [
    # NOMAD shells out to py-spy for on-server profiling rather than importing
    # it; the PyPI distribution is the same Rust binary nixpkgs already ships
    # as pkgs.py-spy.  Repackaging the wheel to satisfy a declaration would add
    # a second copy of the binary for nothing — makeWrapperArgs below puts the
    # real one on the `nomad` executable's PATH instead.
    "py-spy"

    # nomad-lab pins three contrib packages at ==0.63b1, a version nixpkgs
    # never carried (it went 0.61b0 -> 0.64b0).  The pins are there to stop
    # uv's resolver drifting across a lockstep-versioned family, not because of
    # an API break: NOMAD calls only FastAPIInstrumentor.instrument_app,
    # PymongoInstrumentor().instrument() and the elasticsearch equivalent, all
    # stable across a beta bump.  Downgrading twelve otel packages by hand to
    # honour them would be far riskier than relaxing them.
    "opentelemetry-instrumentation-asgi"
    "opentelemetry-instrumentation-pymongo"
    "opentelemetry-instrumentation-elasticsearch"

    # A win32-only marker.  The dependency check evaluates the marker
    # correctly, but the relaxation keeps the metadata honest about a package
    # that has no Linux distribution at all.
    "python-magic-bin"
  ];

  dependencies = [
    ase
    bitarray
    cachetools
    click
    docstring-parser
    elasticsearch
    elasticsearch-dsl
    fsspec
    h5py
    httpx
    jmespath
    jsonpath-ng
    json-stream
    kaleido
    lxml
    matid
    molid
    msglc
    numpy
    openpyxl
    orjson
    pandas
    pathvalidate
    pint
    plotly
    pydantic
    pyinstrument
    pymatgen
    python-keycloak
    python-magic
    pyyaml
    requests
    rfc3161ng
    scipy
    unidecode
    xarray

    beautifulsoup4
    beanie
    blinker
    cryptography
    fastapi
    fastapi-cache2
    gunicorn
    h5grove
    mongoengine
    optimade
    prometheus-client
    pyjwt
    python-logstash
    python-multipart
    rdflib
    starlette
    structlog
    tabulate
    temporalio
    uvicorn
    validators
    zipstream-ng
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-exporter-otlp
    opentelemetry-exporter-otlp-proto-grpc
    opentelemetry-instrumentation-asgi
    opentelemetry-instrumentation-fastapi
    opentelemetry-instrumentation-pymongo
    opentelemetry-instrumentation-elasticsearch
  ]
  ++ uvicorn.optional-dependencies.standard
  ++ pyjwt.optional-dependencies.crypto;

  # jupyterhub, dockerspawner and oauthenticator are in [infrastructure] but
  # deliberately absent above: they exist only for NORTH, the remote-tools
  # JupyterHub, which this deployment does not run.  Nothing imports them
  # eagerly — nomad/jupyterhub_config.py is loaded by jupyterhub itself and
  # `from jupyterhub.app import main` in nomad/cli/admin/run.py:325 sits inside
  # the `nomad admin run hub` handler — so the app and worker start fine
  # without them, provided config.north.enabled stays false (which is what
  # services.nomad-oasis renders).  Adding them back means adding all three,
  # not just one.

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ py-spy ]}"
  ];

  # The sdist deliberately excludes tests (`exclude = ["tests*"]` under
  # [tool.setuptools.packages.find]), and upstream's suite needs a live
  # Elasticsearch, MongoDB and Temporal anyway — it is an integration suite,
  # not a unit one.  That coverage lives in the oasis-minimal and oasis-upload
  # VM tests, which stand the real stack up.
  doCheck = false;

  pythonImportsCheck = [
    "nomad"
    "nomad.config"
    "nomad.datamodel"
    "nomad.parsing"
    # Constructs the whole FastAPI application, so it exercises fastapi,
    # starlette, fastapi-cache2, temporalio and the otel instrumentation
    # together — the combination the version pins above are all about.
    "nomad.app.main"
  ];

  # The module launches this with lib.getExe, which silently falls back to the
  # *package* name; without this it would look for a binary called
  # "nomad-lab", which does not exist.  (And `nomad` at the top level of pkgs
  # is HashiCorp Nomad — unrelated.)
  meta = {
    description = "The NOvel MAterials Discovery (NOMAD) platform, run as a self-hosted Oasis";
    homepage = "https://nomad-lab.eu/";
    downloadPage = "https://pypi.org/project/nomad-lab/";
    license = lib.licenses.asl20;
    mainProgram = "nomad";
    maintainers = [ lib.maintainers.berquist ];
  };
}
