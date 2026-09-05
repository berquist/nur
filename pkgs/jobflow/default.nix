{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  maggma,
  monty,
  networkx,
  pydantic,
  pydantic-settings,
  pydash,
  pyyaml,

  # optional-dependencies
  fireworks,
  matplotlib,
  pydot,
  python-ulid,

  # tests
  pytestCheckHook,
  moto,
}:

buildPythonPackage (finalAttrs: {
  pname = "jobflow";
  version = "0.3.1";
  pyproject = true;
  __structuredAttrs = true;

  # The v0.3.1 tag rather than HEAD, which is thirty-eight commits past it.
  # jobflow-remote asks for `jobflow >= 0.2.1` and atomate2 for `>= 0.1.11`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "jobflow";
    rev = "v${finalAttrs.version}";
    hash = "sha256-g6LxROQu31kODee/VkXF7PJ+/OmlX5AV/xbIKdob+/s=";
  };

  # The same versioningit hole ../qtoolkit falls into, with the same shape:
  # `method = "git"` against a fetchFromGitHub tarball that has no repository,
  # and a `default-tag` that does not help because it only applies when the
  # repository exists and is untagged.  See ../qtoolkit/default.nix for why the
  # top-level `default-version` is the one that covers it, and why the table has
  # to be inserted ahead of the `vcs` sub-table rather than after.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${finalAttrs.version}"

    [tool.versioningit.vcs]'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    maggma
    monty
    networkx
    pydantic
    pydantic-settings
    pydash
    pyyaml
  ];

  optional-dependencies = {
    fireworks = [ fireworks ];
    ulid = [ python-ulid ];
    vis = [
      matplotlib
      pydot
    ];
  };

  # matplotlib and the `vis`/`ulid` extras are check inputs because they buy
  # back six otherwise-skipped tests: four graph-drawing ones in test_flow.py
  # and test_graph.py, one pydot one, and test_uid.py.
  #
  # **fireworks is deliberately not here**, and that is the opposite of this
  # repo's usual rule about supplying a test dependency rather than disabling
  # the test.  tests/managers/test_fireworks.py opens with
  #
  #   pytest.importorskip("fireworks")
  #
  # and its seventeen tests take an `lpad` fixture — a real FireWorks LaunchPad,
  # which is a MongoDB, plus a `mongo_jobstore` on top of it.  Installing
  # fireworks therefore does not fix anything; it converts one clean skip into
  # seventeen ServerSelectionTimeoutErrors, because what is missing is the
  # database rather than the library.  A database is not available here for the
  # licensing reason ../fireworks/default.nix records at length.
  #
  # Leaving it out lets upstream's own guard do the work, with no
  # disabledTestPaths entry to keep in step with a module that may be renamed.
  # The extra is still declared above, so a consumer who has a MongoDB gets it
  # with `jobflow[fireworks]`.
  #
  # Measured: without fireworks, 139 passed / 4 skipped.  With it, 141 passed /
  # 3 skipped / **17 errors**.
  nativeCheckInputs = [
    pytestCheckHook
    moto
  ]
  ++ finalAttrs.passthru.optional-dependencies.ulid
  ++ finalAttrs.passthru.optional-dependencies.vis;

  # HOME and MPLBACKEND for matplotlib, which wants a writable config directory
  # and otherwise tries to autodetect a display.  Same two ../fireworks needs.
  preCheck = ''
    export HOME="$(mktemp -d)"
    export MPLBACKEND=Agg
  '';

  pythonImportsCheck = [
    "jobflow"
    "jobflow.core.flow"
    "jobflow.managers.local"
  ];

  meta = {
    description = "Library for writing computational workflows";
    homepage = "https://github.com/materialsproject/jobflow";
    changelog = "https://github.com/materialsproject/jobflow/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
