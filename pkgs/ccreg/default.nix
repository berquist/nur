{
  lib,
  buildPythonApplication,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  click,
  lwreg,
  numpy,
  psycopg,
  rdkit,
  tqdm,

  # See ../harmonwig/default.nix for why cclib is a defaulted argument and what
  # meta.broken below is protecting.  ccreg/ccreg.py does `import cclib` at
  # module scope — parsing logfiles is the whole point of the package.
  cclib ? null,

  # tests
  pytestCheckHook,
}:

buildPythonApplication {
  pname = "ccreg";
  version = "0.1.0-unstable-2026-01-20";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ghutchis";
    repo = "ccreg";
    rev = "d07aceb5530176ac95109b20f8984d4e574de09e";
    hash = "sha256-93JCmUlRY2xKJNVlNexL0Xm00RSiShJ1oyfyvYGcUXQ=";
  };

  build-system = [ hatchling ];

  # pyproject.toml spells lwreg as
  # `lwreg @ git+https://github.com/rinikerlab/lightweight-registration.git`,
  # a direct URL reference.  pythonRuntimeDepsCheckHook rejects those outright,
  # and the packaged ../lwreg is that same repository — so the requirement is
  # dropped here and the dependency supplied below.
  #
  # rdkit and tqdm are dropped from the other direction: they are real imports
  # that upstream declares only in `[tool.pixi.dependencies]`, where nothing
  # reading the wheel metadata will find them.  They too are supplied below.
  pythonRemoveDeps = [ "lwreg" ];

  dependencies = [
    click
    lwreg
    numpy
    psycopg
    rdkit
    tqdm
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "ccreg"
    "ccreg.ccreg"
  ];

  meta = {
    description = "Computational chemistry registration system built on lwreg";
    homepage = "https://github.com/ghutchis/ccreg";
    license = lib.licenses.mit;
    mainProgram = "ccreg";
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through the flake; see the cclib argument above.
    broken = cclib == null;
  };
}
