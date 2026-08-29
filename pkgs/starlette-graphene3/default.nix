{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  poetry-core,

  # dependencies
  graphene,
  graphql-core,
  starlette,

  # tests
  pytestCheckHook,
  pytest-asyncio,
  graphene-file-upload,
  httpx,
  python-multipart,
}:

buildPythonPackage rec {
  pname = "starlette-graphene3";
  version = "0.6.1-unstable-2023-06-12";
  pyproject = true;

  # The tag is 0.6.0 and pyproject.toml already says 0.6.1, so the version
  # comes from the source rather than from `git describe`.  Not fetchPypi: the
  # sdist carries no tests.
  src = fetchFromGitHub {
    owner = "ciscorn";
    repo = "starlette-graphene3";
    rev = "cfe6a45f3163649f605fd1fa0f10b492b6721c8b";
    hash = "sha256-SULYF34eI5DeOonX2v0g2jiS58hu1MUNQDYqavT0vws=";
  };

  # `poetry.masonry.api` is the pre-1.0 backend name, and the build-system
  # requirement is on `poetry` itself rather than poetry-core.  nixpkgs carries
  # only poetry-core, which implements the same interface under its modern
  # name.  The metadata this project declares is plain `[tool.poetry]` with no
  # plugins, so the rename is the whole of the difference.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["poetry>=0.12"]' 'requires = ["poetry-core"]' \
      --replace-fail 'build-backend = "poetry.masonry.api"' \
                     'build-backend = "poetry.core.masonry.api"'
  '';

  build-system = [ poetry-core ];

  dependencies = [
    graphene
    graphql-core
    starlette
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio

    # tests/conftest.py does `from graphene_file_upload.scalars import Upload`
    # at module scope, so nothing collects without it.  nixpkgs has no
    # graphene-file-upload; ../graphene-file-upload is ours.
    graphene-file-upload

    # starlette's TestClient is an httpx client, and the multipart tests post
    # file uploads, which starlette parses through python-multipart.
    httpx
    python-multipart
  ];

  # A single module, `src/starlette_graphene3.py`, so there are no submodules to
  # name here.
  pythonImportsCheck = [ "starlette_graphene3" ];

  meta = {
    description = "GraphQL ASGI app for Starlette, using Graphene v3";
    homepage = "https://github.com/ciscorn/starlette-graphene3";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
