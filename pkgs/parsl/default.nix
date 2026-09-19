{
  lib,
  buildPythonPackage,
  fetchPypi,
  pythonOlder,

  # build-system
  setuptools,

  # dependencies (requirements.txt)
  dill,
  filelock,
  psutil,
  pyzmq,
  requests,
  setproctitle,
  sortedcontainers,
  tblib,
  typeguard,
  typing-extensions,

  # optional-dependencies
  sqlalchemy,
  pydot,
  networkx,
  flask,
  flask-sqlalchemy,
  pandas,
  plotly,
  python-daemon,
  boto3,
  kubernetes,
  google-auth,
  google-api-python-client,
  gssapi,
  pyyaml,
  cffi,
  jsonschema,
  globus-sdk,

  # tests (test-requirements.txt)
  pytestCheckHook,
  pytest-random-order,
}:

buildPythonPackage rec {
  pname = "parsl";
  version = "2026.9.7";
  pyproject = true;

  disabled = pythonOlder "3.10";

  # Source distribution, not a wheel: setup.py reads parsl/version.py and
  # requirements.txt at build time, neither of which ships in the wheel.
  #
  # `fetchPypi` rather than the `fetchurl` this used to be, and the reason is
  # the updater rather than the build — the two fetch the same bytes to the same
  # store path.  pythonhosted addresses a file by a hash of its contents
  # (`packages/16/94/32047135…/parsl-2026.7.27.tar.gz`), which cannot be derived
  # from a version, so `nix-update` could neither learn what the newest release
  # was — it only recognises `mirror://pypi` URLs — nor construct the URL of one
  # if it had.  This package was the sole permanent `failed` row in the scan for
  # that reason.  `mirror://pypi/p/parsl/parsl-${version}.tar.gz` is derivable,
  # so a bump is now an ordinary version rewrite.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-zDKJAUKJX/lznuUF1VaDloEfv3MIxQsavhCw/sWqolk=";
  };

  # parsl/tests/conftest.py still declares pytest_ignore_collect with the
  # py.path.local signature that pytest removed in 9.x, so pluggy refuses to
  # register the conftest and the whole run dies before collection.
  # https://github.com/Parsl/parsl/issues/4051 — still open upstream, so this
  # stays until they rework it.
  patches = [ ./conftest.patch ];

  build-system = [ setuptools ];

  # Core requirements.txt bounds are all satisfiable against nixpkgs as-is.
  # Only the visualization extra pins an upper bound we sit above
  # (networkx>=3.2,<3.3).
  pythonRelaxDeps = [ "networkx" ];

  dependencies = [
    dill
    filelock
    psutil
    pyzmq
    requests
    setproctitle
    sortedcontainers
    tblib
    typeguard
    typing-extensions
  ];

  # Not `rec`: attribute names like `kubernetes` and `gssapi` collide with the
  # function arguments of the same name, and under `rec` the attribute wins,
  # giving a list that contains itself.
  optional-dependencies =
    let
      extras = {
        monitoring = [ sqlalchemy ];
        visualization = [
          pydot
          networkx
          flask
          flask-sqlalchemy
          pandas
          plotly
          python-daemon
        ];
        aws = [ boto3 ];
        kubernetes = [ kubernetes ];
        google_cloud = [
          google-auth
          google-api-python-client
        ];
        gssapi = [ gssapi ];
        flux = [
          pyyaml
          cffi
          jsonschema
        ];
        globus_transfer = [ globus-sdk ];

        # Extras deliberately omitted because their dependencies are not in
        # nixpkgs (or are docs-only): docs, azure, workqueue (work_queue /
        # cctools), proxystore, radical-pilot, globus_compute.
      };
    in
    extras // { all = lib.concatLists (lib.attrValues extras); };

  nativeCheckInputs = [
    pytestCheckHook
    pytest-random-order
  ]
  ++ optional-dependencies.all;

  # Only the unit tests are run. The rest of parsl/tests/ launches executors,
  # binds sockets, shells out to schedulers and in places reaches the network,
  # none of which works in the sandbox. --config is required by
  # parsl/tests/conftest.py.
  pytestFlags = [
    "parsl/tests/unit"
    "--random-order"
    "--config"
    "local"
  ];

  disabledTests = [
    # Globus Compute package not being picked up?
    "test_gc_executor_resets_uep_after_submit"
    "test_gc_executor_label"
    "test_gc_executor_resets_spec_after_submit"
    "test_gc_executor_shuts_down_asynchronously"
    "test_gc_executor_label_default"
    "test_gc_executor_happy_path"
    "test_gc_executor_mock_spec"
  ];

  pythonImportsCheck = [
    "parsl"
    "parsl.executors"
    "parsl.providers"
  ];

  meta = {
    description = "Simple data dependent workflows in Python";
    homepage = "https://github.com/Parsl/parsl";
    changelog = "https://github.com/Parsl/parsl/releases/tag/${version}";
    license = lib.licenses.asl20;
    maintainers = [ ];
    mainProgram = "parsl-perf";
  };
}
