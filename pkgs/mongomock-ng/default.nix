{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  packaging,
  pytz,
  sentinels,

  # optional-dependencies
  pandas,
  pymongo,

  # tests
  pytestCheckHook,
}:

buildPythonPackage (finalAttrs: {
  pname = "mongomock-ng";
  version = "7.11.1";
  pyproject = true;
  __structuredAttrs = true;

  # The import name is `mongomock_ng`, not `mongomock`, and that is what makes
  # this safe to carry beside the two mongomocks already in this tree: nixpkgs'
  # `mongomock` 4.3.0, and ../mongomock-persistence, which monkey-patches
  # `mongomock.store` for fireworks.  Different top-level module, so nothing
  # patches anything of ours.  maggma spells it `import mongomock_ng as
  # mongomock` (stores/mongolike.py:14), which is where the confusion comes
  # from — that alias is local to the module.
  src = fetchFromGitHub {
    owner = "engFelipeMonteiro";
    repo = "mongomock-ng";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Kb1Mc2qS/qlgWEniOUzN+IV4x1mK8d2Nxkss57RsO6E=";
  };

  build-system = [ hatchling ];

  dependencies = [
    packaging
    pytz
    sentinels
  ];

  # pyexecjs is upstream's fourth extra and is deliberately absent: nixpkgs does
  # not carry it, it exists to evaluate `$where` JavaScript through a node
  # runtime, and it costs exactly three skipped tests.
  optional-dependencies = {
    pandas = [ pandas ];
    pymongo = [ pymongo ];
  };

  # NO_LOCAL_MONGO is upstream's own switch, read by four test modules and set
  # by their own CI in .github/workflows/lint-and-test.yml.  Without it the
  # server-backed classes do not skip, they hang and then fail:
  #
  #   pymongo.errors.ServerSelectionTimeoutError:
  #     127.0.0.1:27017: [Errno 111] Connection refused
  #
  # Twelve of them, thirty seconds of server selection apiece, which is 6:27 of
  # the suite's 6:29.  With the variable set it is 1315 passed in 1.8s and the
  # twelve become skips.  A real MongoDB is not the alternative — every
  # mongodb-ce in the locked nixpkgs is SSPL and `meta.license.free = false`,
  # which ci.nix filters on; ../fireworks/default.nix carries the long version
  # of that argument.  Note these want a *replica set* (`?replicaSet=rs0`), so
  # even a permissive build would need more than a bare mongod.
  #
  # Setting it here rather than in `env` for symmetry with the `preCheck` that
  # ../fireworks needs for the same class of problem, and because a reader
  # looking for why the database tests are quiet will look at one of the two.
  preCheck = ''
    export NO_LOCAL_MONGO=1
  '';

  # Both extras are check inputs, and they pull their weight: pymongo is what
  # most of the suite compares behaviour against, and pandas recovers the two
  # tests that skip themselves with "pandas not installed".
  nativeCheckInputs = [
    pytestCheckHook
  ]
  ++ finalAttrs.passthru.optional-dependencies.pandas
  ++ finalAttrs.passthru.optional-dependencies.pymongo;

  pythonImportsCheck = [
    "mongomock_ng"
    "mongomock_ng.collection"
  ];

  meta = {
    description = "Fake pymongo stub for testing MongoDB-dependent code, maintained fork of mongomock";
    homepage = "https://github.com/engFelipeMonteiro/mongomock-ng";
    changelog = "https://engFelipeMonteiro.github.io/mongomock-ng/CHANGELOG/";
    license = lib.licenses.isc;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
