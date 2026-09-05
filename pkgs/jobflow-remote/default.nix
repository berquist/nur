{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  fabric,
  flufl-lock,
  jobflow,
  monty,
  psutil,
  pydantic,
  pymongo,
  python-dateutil,
  qtoolkit,
  rich,
  ruamel-yaml,
  schedule,
  supervisor,
  tomlkit,
  typer,

  # tests
  pytestCheckHook,
  pytest-mock,
}:

buildPythonPackage (finalAttrs: {
  pname = "jobflow-remote";
  version = "1.0.1";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "Matgenix";
    repo = "jobflow-remote";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PyfU8Aj1+GYUdJtMh/HLUbmh8dWpzaDNW9SfY33xihw=";
  };

  # The third package in this family with the same versioningit hole; see
  # ../qtoolkit/default.nix for what `default-version` does and why the table
  # has to precede the `vcs` sub-table.
  #
  # The second hunk is upstream's, not ours.  tests/test_jobflow_remote.py has
  # asserted `__version__.startswith("0.")` since before 1.0.0 and was never
  # updated for the release, so it fails against the version it is packaged at:
  #
  #   AssertionError: unexpected __version__='1.0.1'
  #
  # Still live at v1.0.1, which is upstream's tip.  Rewritten rather than
  # deselected, and pinned to the exact version rather than to "1.", because
  # that turns a stale smoke test into a real check on the hunk above it: if the
  # `default-version` insertion ever stops taking, versioningit falls back to
  # the `default-tag` of 0.0.1 and this is what says so.  Deselecting it would
  # throw away the only assertion in the suite that looks at the version at all.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${finalAttrs.version}"

    [tool.versioningit.vcs]'

    substituteInPlace tests/test_jobflow_remote.py \
      --replace-fail \
        'assert __version__.startswith("0."), f"unexpected {__version__=}"' \
        'assert __version__ == "${finalAttrs.version}", f"unexpected {__version__=}"'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # `pymongo >= 4.4, < 4.11` against nixpkgs' 4.17.0.
  #
  # The upper bound came in as upstream's 8dd709d, "Hot fix to pin pymongo
  # version to lower than 4.11", in February 2025, with no reason recorded in
  # the commit or the changelog it touched.  The circumstantial answer is
  # mongomock: the old one caps pymongo below 4.11, and maggma carried the same
  # bound until it switched to mongomock-ng expressly to drop it (its c2c38993,
  # "Remove pymongo<4.11 pin and switch to mongomock-ng").  That makes this a
  # test-time constraint inherited from a mock, not a runtime API limit.
  #
  # Consistent with that, everything jobflow-remote actually imports is present
  # and unchanged in 4.17.0: `ReturnDocument`, `errors.PyMongoError`,
  # `collection.Collection`, `client_session.ClientSession`, and the
  # `find_one_and_update` / `update_one` calls in utils/db.py.  Checked against
  # the 4.17.0 in this closure rather than assumed.
  #
  # There is also no version that would satisfy everyone: ../mongomock-ng wants
  # `pymongo >= 4.11` for its own pymongo extra, so one pymongo cannot honour
  # both bounds and the newer one is the only side that has a package.
  pythonRelaxDeps = [ "pymongo" ];

  dependencies = [
    fabric
    flufl-lock
    jobflow
    monty
    psutil
    pydantic
    pymongo
    python-dateutil
    qtoolkit
    rich
    ruamel-yaml
    schedule
    supervisor
    tomlkit
    typer
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-mock
  ];

  # Upstream splits its suite into three directories and stamps a marker on each
  # in tests/conftest.py's pytest_collection_modifyitems, which *raises* if a
  # test ends up in none of them — so the split is exact and maintained.
  #
  #   tests/unit          what runs here
  #   tests/db            a MongoDB, which is unavailable for the licensing
  #                       reason ../fireworks/default.nix records
  #   tests/integration   containers driven through python-on-whales, plus real
  #                       SLURM and SSH workers
  #
  # Paths rather than `disabledTestMarks = [ "db" "integration" ]`, which would
  # be the tidier spelling and does not work: marker filtering happens after
  # collection, and collection imports the module.  tests/integration would
  # still be imported, and it imports python-on-whales at module scope.
  # --ignore-glob, which disabledTestPaths generates, is applied first.
  #
  # Note the integration modules also carry `pytest.mark.skipif(not
  # os.environ.get("CI"))`, so they would skip themselves once imported — the
  # import is the only thing that has to be prevented, and it is enough of a
  # reason on its own.
  disabledTestPaths = [
    "tests/db"
    "tests/integration"
  ];

  pythonImportsCheck = [
    "jobflow_remote"
    "jobflow_remote.jobs.daemon"
    "jobflow_remote.jobs.runner"
  ];

  meta = {
    description = "Job manager for running jobflow workflows on remote resources";
    homepage = "https://github.com/Matgenix/jobflow-remote";
    changelog = "https://github.com/Matgenix/jobflow-remote/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    mainProgram = "jf";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
