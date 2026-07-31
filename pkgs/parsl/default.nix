{
  lib,
  buildPythonPackage,
  fetchurl,
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
  pytest-cov,
  pytest-random-order,
}:

buildPythonPackage rec {
  pname = "parsl";
  version = "2026.7.27";
  pyproject = true;

  disabled = pythonOlder "3.10";

  # Source distribution, not a wheel: setup.py reads parsl/version.py and
  # requirements.txt at build time, neither of which ships in the wheel.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/16/94/32047135b76f8c2c56dc87cc2e53e41aa7848659e0d6f82f23f984d54552/parsl-${version}.tar.gz";
    hash = "sha256-ox4ynnCLBb6oN9zd+WR+k3iFFPByR20+mvb0C+BNbH4=";
  };

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

  optional-dependencies = rec {
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
    all = lib.flatten [
      monitoring
      visualization
      aws
      kubernetes
      google_cloud
      gssapi
      flux
      globus_transfer
    ];
  };

  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
    pytest-random-order
    pandas
    sqlalchemy
  ];

  # Only the unit tests are run. The rest of parsl/tests/ launches executors,
  # binds sockets, shells out to schedulers and in places reaches the network,
  # none of which works in the sandbox. --config is required by
  # parsl/tests/conftest.py.
  pytestFlags = [
    "parsl/tests/unit"
    "--config"
    "local"
  ];

  # disabledTestPaths = [
  #   # needs a working MPI runtime (test-requirements.txt pulls in mpi4py)
  #   "parsl/tests/test_mpi_apps"
  # ];

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

# To fill in the hash:
#
#   nix store prefetch-file --json \
#     https://files.pythonhosted.org/packages/16/94/32047135b76f8c2c56dc87cc2e53e41aa7848659e0d6f82f23f984d54552/parsl-2026.7.27.tar.gz
#
# and paste the returned SRI string in place of lib.fakeHash.
#
# Build it with:
#
#   nix-build -E 'with import <nixpkgs> {}; python3Packages.callPackage ./default.nix {}'
