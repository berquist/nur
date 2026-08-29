{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  six,

  # tests
  pytestCheckHook,
  pytest-django,
  django,
  graphene,
  graphene-django,
}:

buildPythonPackage rec {
  pname = "graphene-file-upload";
  version = "1.3.0-unstable-2021-11-30";
  pyproject = true;

  # Twenty-two commits past v1.3.0, and not fetchPypi: the sdist ships no
  # `tests/`.  See the sdist-has-no-tests trap in ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "lmcgartland";
    repo = "graphene-file-upload";
    rev = "70efa3238ba5155ee5d2f4a2dbbb519884bdca59";
    hash = "sha256-kOvysZFRMqiqBkGYKVMxfhZK3JyVAsN5zaPZavKnFBI=";
  };

  build-system = [ setuptools ];

  # `install_requires` is six and nothing else.  The web frameworks are extras:
  # graphene_file_upload.flask wants flask and flask-graphql,
  # graphene_file_upload.django wants graphene-django, and the top-level
  # `scalars` module — the only part this repo uses — wants neither.
  dependencies = [ six ];

  # tests/conftest.py calls `django.conf.settings.configure(...)` at import
  # time, so Django is needed to collect *any* test module, including
  # test_utils.py which touches nothing Django.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-django
    django
    graphene
    graphene-django
  ];

  # flask-graphql is not in nixpkgs, and tests/test_flask.py imports
  # graphene_file_upload.flask, which imports it at module scope.  Supplying
  # the dependency is what ../../AGENTS.md asks for and would mean packaging
  # flask-graphql — a project last released in 2020, for the Flask 1.x request
  # API — to run four tests of a compatibility shim this repo never imports.
  # The Django half of the same suite does run.
  #
  # It doubles as the canary: `disabledTestPaths` aborts the build when a glob
  # matches nothing, which is the cheapest proof the suite was collected at all.
  disabledTestPaths = [ "tests/test_flask.py" ];

  # Neither framework shim is importable here, for two different reasons.
  # `graphene_file_upload.flask` wants flask-graphql, which nixpkgs lacks.
  # `graphene_file_upload.django` imports `graphene_django.views`, and
  # graphene_django reads `settings.DEBUG` at import time:
  #
  #   django.core.exceptions.ImproperlyConfigured: Requested setting DEBUG,
  #   but settings are not configured.
  #
  # A bare import outside a Django project is exactly what that error is for.
  # The suite gets there through tests/conftest.py, which calls
  # `settings.configure(...)` in `pytest_configure`; an import check has no
  # such hook, and inventing one would be testing Django's bootstrap rather
  # than this package.
  pythonImportsCheck = [
    "graphene_file_upload"
    "graphene_file_upload.scalars"
    "graphene_file_upload.utils"
  ];

  meta = {
    description = "File upload support for GraphQL mutations in Graphene Django and Flask-GraphQL";
    homepage = "https://github.com/lmcgartland/graphene-file-upload";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
