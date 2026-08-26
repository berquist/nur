{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  mongomock,
  pymongo,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "mongomock-persistence";
  # 0.0.5, not the 0.0.4 that `git describe` reports two commits back: setup.cfg
  # on this commit already declares 0.0.5.  Same tag-behind-source shape as
  # ../fireworks, which is also the only consumer.
  version = "0.0.5-unstable-2024-11-28";
  pyproject = true;

  # Carried here only so ../fireworks' database tests can run without a real
  # MongoDB.  nixpkgs has `mongomock` but not this wrapper, and every mongodb-ce
  # in the locked nixpkgs is unfree — see the MongoDB note in
  # ../fireworks/default.nix for why that rules the real server out.
  #
  # The import name is `mongomock_persistence`; the distribution is
  # `mongomock-persistence`.
  src = fetchFromGitHub {
    owner = "ikondov";
    repo = "mongomock-persistence";
    rev = "0cc953de9d419946e455e0709b0869b50a06be9b";
    hash = "sha256-vXigf2K/JN9dCRg6tR4QxflVDvRPGLZLt7HAnEeYSoA=";
  };

  build-system = [ setuptools ];

  dependencies = [
    mongomock
    pymongo
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # The suite is one module, tests/test__persistence.py, and it does run: the
  # sdist-has-no-tests trap in AGENTS.md does not apply because src comes from
  # git.  Worth checking after any bump all the same — `tests/` carries no
  # __init__.py, which is the only reason setup.cfg's bare `packages = find:`
  # does not install it as a second top-level package.  Adding one would both
  # pollute site-packages and shadow the suite.
  #
  # Both tests drive MONGOMOCK_SERVERSTORE_FILE through a NamedTemporaryFile and
  # clean up after themselves, so no writable HOME and no server are needed.

  pythonImportsCheck = [ "mongomock_persistence" ];

  meta = {
    description = "Mongomock with persistence, backing a mock MongoDB with a JSON file";
    homepage = "https://github.com/ikondov/mongomock-persistence";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
