{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  click,
  numpy,
  psycopg,
  rdkit,
  tqdm,

  # tests
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "lwreg";
  version = "0.2.0-unstable-2026-02-09";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "rinikerlab";
    repo = "lightweight-registration";
    rev = "8e67b5cb61b56913a49f6108ee07917937baa43e";
    hash = "sha256-BZvDDihx9BwDPiwlfcWzHPplutWv00QPBZlnUO8OyTs=";
  };

  build-system = [ hatchling ];

  # pyproject.toml declares only `Click`.  The other four are real imports that
  # upstream expects conda to have supplied — its tox config installs
  # `rdkit rdkit-postgresql postgresql psycopg tqdm` before running anything,
  # and lwreg/utils.py imports rdkit and numpy at module scope.
  #
  # psycopg is the one genuine option: lwreg supports SQLite and PostgreSQL
  # back ends and imports psycopg behind a try/except.  It is included anyway
  # because ccreg — the only consumer here — exists to register into a real
  # database, and its own `postgresql` extra asks for exactly this.
  dependencies = [
    click
    numpy
    psycopg
    rdkit
    tqdm
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # No PostgreSQL is provided on purpose.  lwreg/test_lwreg.py probes for a
  # running server and falls back to SQLite when there is none, so the suite
  # runs either way; standing one up would only add the PostgreSQL-specific
  # cases, and pgtest cannot supply the `rdkit-postgresql` cartridge that half
  # of those need.
  pythonImportsCheck = [
    "lwreg"
    "lwreg.utils"
    "lwreg.standardization_lib"
  ];

  meta = {
    description = "Lightweight chemical compound registration system";
    homepage = "https://github.com/rinikerlab/lightweight-registration";
    license = lib.licenses.mit;
    mainProgram = "lwreg";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
