{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiofiles,
  firecrest-streamer,
  httpx,
  packaging,
  pyjwt,
  pyyaml,
  requests,
  typer,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  pytest-httpserver,
}:

buildPythonPackage rec {
  pname = "pyfirecrest";
  version = "3.9.0";
  pyproject = true;

  # fetchFromGitHub for consistency with the rest of this family rather than
  # out of necessity: unlike most of them, pyfirecrest declares no
  # `[tool.flit.sdist] exclude`, so its sdist would carry the tests too.  See
  # the sdist-has-no-tests trap in ../../AGENTS.md for why that is worth
  # checking rather than assuming either way.
  src = fetchFromGitHub {
    owner = "eth-cscs";
    repo = "pyfirecrest";
    tag = "v${version}";
    hash = "sha256-6XKHOh6t4yHTO33ph8QkobcqyBILF7+DHbxcXV2toJI=";
  };

  build-system = [ flit-core ];

  # firecrest-streamer is not optional despite what its name suggests:
  # firecrest/__init__.py imports `v2`, whose _async/Client.py opens with
  # `from streamer import streamer_client`, so `import firecrest` fails without
  # it.  nixpkgs has no such package; ../firecrest-streamer builds it out of the
  # FirecREST server monorepo, where it lives as a subdirectory.
  dependencies = [
    aiofiles
    firecrest-streamer
    httpx
    packaging
    pyjwt
    pyyaml
    requests
    typer
  ];

  # `cd tests`, because the fixtures are opened by a path relative to the
  # working directory: tests/v2/handlers.py has `read_json_file(filename)` doing
  # a bare `open("v2/responses/systems.json")`.  Run from the source root, as
  # pytestCheckHook does, 88 of the 437 tests fail with
  #
  #   FileNotFoundError: [Errno 2] No such file or directory:
  #   'v2/responses/systems.json'
  #
  # Upstream's own CI says the same thing in its own way —
  # .github/workflows/testing.yml sets `working-directory: ./tests` for the
  # pytest step — so this is matching their invocation rather than patching
  # around it.
  preCheck = ''
    cd tests
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # The suite mocks the FirecREST REST API rather than talking to one: every
    # test module builds a pytest-httpserver instance and registers werkzeug
    # handlers against it, and the async half needs pytest-asyncio to drive the
    # v2 client's coroutines.
    pytest-asyncio
    pytest-httpserver
  ];

  # `typer[all]` in the metadata, which no longer means anything — typer merged
  # the extra into the base distribution — but nixpkgs' typer already carries
  # rich and shellingham, so the CLI tests that use `typer.testing.CliRunner`
  # have what they need.
  pythonImportsCheck = [
    "firecrest"
    "firecrest.v1"
    "firecrest.v2"
    "firecrest.cli_script"
  ];

  meta = {
    description = "Python client for the FirecREST API";
    homepage = "https://github.com/eth-cscs/pyfirecrest";
    changelog = "https://github.com/eth-cscs/pyfirecrest/blob/main/CHANGELOG.md";
    license = lib.licenses.bsd3;
    mainProgram = "firecrest";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
