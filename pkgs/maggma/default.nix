{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  aioitertools,
  boto3,
  click,
  dnspython,
  jsonlines,
  jsonschema,
  mongomock-ng,
  monty,
  msgpack,
  numpy,
  orjson,
  pandas,
  paramiko,
  pydantic,
  pydantic-settings,
  pydash,
  pymongo,
  python-dateutil,
  pyzmq,
  ruamel-yaml,
  tqdm,

  # optional-dependencies
  azure-identity,
  azure-storage-blob,
  fastapi,
  hvac,
  memray,
  pymatgen,
  uvicorn,

  # tests
  pytestCheckHook,
  moto,
  pytest-asyncio,
  pytest-mock,
  pytest-timeout,
  responses,
  starlette,
}:

buildPythonPackage (finalAttrs: {
  pname = "maggma";
  version = "0.74.0";
  pyproject = true;
  __structuredAttrs = true;

  # The v0.74.0 tag rather than HEAD, which is twenty-six commits past it.
  # jobflow asks for `maggma >= 0.72.0`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "maggma";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ee3xeaXuUXT6LEQCZ3+jw9caTt445zkKg+xtypYdQ5c=";
  };

  # setuptools_scm reads the version from git, and fetchFromGitHub hands over a
  # tarball with no .git.  Same shape as ../sella, and unlike ../qtoolkit's
  # versioningit this one has an environment variable for it, so no patch is
  # needed.  Derived from `version` rather than repeated, so the two cannot
  # drift.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  build-system = [
    setuptools
    setuptools-scm
  ];

  # paramiko>=5.0 against nixos-26.05's 4.0.0, where the wheel check stops the
  # build outright:
  #
  #   Checking runtime dependencies for maggma-0.74.0-py3-none-any.whl
  #     - paramiko>=5.0 not satisfied by version 4.0.0
  #
  # Both unstable legs carry 5.0.0 and need none of this; 26.05 is the only one
  # that does, the same split ../fireworks records for monty.
  #
  # The pin came from upstream's fbb8d5ce, "sshtunnel: changes for paramiko
  # 5.0.0", which rewrote _load_private_key in stores/ssh_tunnel.py from a loop
  # over RSAKey/ECDSAKey/Ed25519Key/DSSKey into a single call to the abstract
  # `paramiko.PKey.from_private_key_file`.  Relaxing it is safe here for a
  # reason worth measuring rather than assuming, and the measurement is not the
  # one you would expect: that call raises
  #
  #   TypeError: PKey.__init__() got an unexpected keyword argument 'filename'
  #
  # on paramiko **5.0.0 and 4.0.0 alike**, for both RSA and Ed25519 keys.  The
  # abstract PKey is documented as "useless on the abstract PKey class" in both
  # versions' own docstring — the auto-detecting entry point is `PKey.from_path`,
  # which upstream did not use.  So the pin buys nothing for the function it was
  # raised for, and 4.0.0 is not worse than 5.0.0 here; it is identical.
  #
  # Everything else maggma touches — Transport, AuthenticationException,
  # SSHException, PKey as an annotation — is present in 4.0.0.  Only DSSKey is
  # gone, and the rewrite above stopped naming it.
  #
  # Note the affected path is untested here either way: tests/stores/
  # test_ssh_tunnel.py needs an sshd and a MongoDB behind it, and is in
  # disabledTestPaths below.
  pythonRelaxDeps = [ "paramiko" ];

  dependencies = [
    aioitertools
    boto3
    click
    dnspython
    jsonlines
    jsonschema
    # Not nixpkgs' `mongomock`, and not ../mongomock-persistence either — a
    # third, separately-named distribution whose import path is `mongomock_ng`.
    # maggma spells it `import mongomock_ng as mongomock` in
    # stores/mongolike.py, which is where the three get confused for each other.
    mongomock-ng
    monty
    msgpack
    # monty imports numpy unconditionally in json.py and does not propagate it
    # on nixos-26.05; maggma needs numpy in its own right anyway.  See
    # ../fireworks/default.nix for the channel split.
    numpy
    orjson
    pandas
    paramiko
    pydantic
    pydantic-settings
    pydash
    pymongo
    python-dateutil
    pyzmq
    ruamel-yaml
    tqdm
  ];

  # montydb and mongogrant are upstream's two remaining extras and are absent:
  # nixpkgs carries neither, and nothing on the jobflow path asks for them.
  # Their tests skip themselves — test_mongolike.py guards the montydb ones
  # behind `requires_montydb`.
  optional-dependencies = {
    api = [
      fastapi
      uvicorn
    ];
    azure = [
      azure-identity
      azure-storage-blob
    ];
    memray = [ memray ];
    vault = [ hvac ];
    vasp = [ pymatgen ];
  };

  nativeCheckInputs = [
    pytestCheckHook
    moto
    pytest-asyncio
    pytest-mock
    pytest-timeout
    responses
    starlette
  ]
  ++ finalAttrs.passthru.optional-dependencies.api
  ++ finalAttrs.passthru.optional-dependencies.vault;

  # pytest-xdist is deliberately absent from that list even though upstream's
  # `testing` extra names it.  In nixpkgs it is not an inert dependency: its
  # setup hook appends `--numprocesses=$NIX_BUILD_CORES` on its own, and these
  # tests share store names and a builder working directory.  ../fireworks
  # carries the long version of what that costs.

  # maggma has no offline mode.  Its own CI (.github/workflows/testing.yml)
  # brings up a `mongo:5.0` service and an Azurite container and runs the whole
  # suite against them; there is no NO_LOCAL_MONGO-style switch of the kind
  # ../mongomock-ng offers, and the `mongostore` fixture in test_mongolike.py
  # builds a MongoStore and calls .connect() with no guard at all.  A real
  # MongoDB is not available here for the licensing reason ../fireworks records
  # at length — every mongodb-ce in the locked nixpkgs is SSPL, and ci.nix
  # filters on meta.license.free.
  #
  # So the six modules that reach a live server go, and so do the two that need
  # something else running:
  #
  #   test_mongolike, test_gridfs, test_advanced_stores, test_compound_stores,
  #   test_shared_stores   a MongoDB on 127.0.0.1:27017
  #   test_azure           Azurite, which upstream documents as a `docker run`
  #                        at the top of the file
  #   test_ssh_tunnel      an sshd, plus a MongoDB behind it
  #   cli/test_init        a MongoDB, reached through the generated config
  #
  # What is left is the half that does not need a service: the api, builders and
  # remaining cli modules, test_file_store, test_open_data and test_aws — the
  # last two being S3, which moto mocks in-process — plus test_utils and
  # test_validator.  That is the part jobflow actually links against; jobflow
  # itself uses MemoryStore and JSONStore, both of which test_mongolike covers
  # and which are the loss worth noting here.
  disabledTestPaths = [
    "tests/cli/test_init.py"
    "tests/stores/test_advanced_stores.py"
    "tests/stores/test_azure.py"
    "tests/stores/test_compound_stores.py"
    "tests/stores/test_gridfs.py"
    "tests/stores/test_mongolike.py"
    "tests/stores/test_shared_stores.py"
    "tests/stores/test_ssh_tunnel.py"
  ];

  # Two stragglers in test_aws.py, which is otherwise entirely moto-mocked and
  # worth keeping: `test_eq` and `test_index_store_kwargs` take the module's
  # `mongostore` fixture, which builds a MongoStore on localhost:27017 to serve
  # as an S3Store's *index* store.  Both error in setup with
  # ServerSelectionTimeoutError, and they are the only two of the module's
  # thirty-odd that reach a server.
  #
  # **disabledTests, not disabledTestPaths.**  This is the one place in this
  # repo where a `::` entry would not work, and it fails *silently* — no error,
  # nothing excluded, the build just keeps failing the same two tests.
  # tests/conftest.py defines a pytest_itemcollected hook that rewrites
  # `item._nodeid` for prettier output:
  #
  #   tests/stores/test_aws.py::test_eq  ->  stores/aws::eq
  #
  # pytest_itemcollected runs during collection; --deselect is applied later, in
  # pytest_collection_modifyitems, and compares against the nodeid *as it then
  # stands*.  By that point the real one is gone.  `-k`, which disabledTests
  # generates, matches `item.name` instead — the hook never touches that — so it
  # still sees `test_eq`.  Verified both ways against a reduced copy of that
  # conftest: --deselect left 3 of 3 running, -k deselected 2.
  #
  # Both names are unique across every module this build still collects, so the
  # substring match `-k` does is exact here.
  disabledTests = [
    "test_eq"
    "test_index_store_kwargs"
  ];

  pythonImportsCheck = [
    "maggma"
    "maggma.stores"
    "maggma.stores.mongolike"
  ];

  meta = {
    description = "Framework to develop data pipelines from files on disk to a dissemination API";
    homepage = "https://github.com/materialsproject/maggma";
    changelog = "https://github.com/materialsproject/maggma/blob/v${finalAttrs.version}/docs/CHANGELOG.md";
    license = lib.licenses.bsd3;
    mainProgram = "mrun";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
