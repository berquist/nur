{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  click,
  websockets,
}:

buildPythonPackage rec {
  pname = "firecrest-streamer";
  version = "0.0.21";
  pyproject = true;

  # One package inside the FirecREST v2 server monorepo, at
  # src/firecrest-streamer/, which is why `src` is the whole repository and
  # sourceRoot picks the subdirectory out.  There is no tag for the streamer
  # itself — the repository's tags version the server — so this is pinned by
  # rev, and `version` is the one its own pyproject.toml declares.
  src = fetchFromGitHub {
    owner = "eth-cscs";
    repo = "firecrest-v2";
    rev = "1b033cb3dee78e2f39799fb5e9ca1461713bbced";
    hash = "sha256-i7Cj4N1QyRLwipHhXkXW7EbtXD89KoDv8nYuc6uNzaw=";
  };

  sourceRoot = "${src.name}/src/firecrest-streamer";

  build-system = [ hatchling ];

  # `asyncio` is declared as a dependency and is the standard library.  The
  # thing on PyPI under that name is a 2015 snapshot of the stdlib module for
  # Python 3.3, which nixpkgs rightly does not carry; leaving the requirement in
  # place fails pythonRuntimeDepsCheckHook on a name that can never resolve.
  # streamer_client.py's `import asyncio` gets the real one either way.
  pythonRemoveDeps = [ "asyncio" ];

  dependencies = [
    click
    websockets
  ];

  # No tests: the streamer subdirectory ships none, and the monorepo's own
  # tests/ exercises the FirecREST server rather than this package.  The import
  # check is therefore the whole check, and it is worth naming the two modules
  # that matter — pyfirecrest imports `streamer.streamer_client` at module
  # scope, which is the entire reason this package exists here.
  pythonImportsCheck = [
    "streamer"
    "streamer.streamer_client"
    "streamer.streamer_core"
  ];

  meta = {
    description = "File streamer over websockets, used by pyfirecrest for large transfers";
    homepage = "https://github.com/eth-cscs/firecrest-v2";
    license = lib.licenses.bsd3;
    mainProgram = "streamer";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
