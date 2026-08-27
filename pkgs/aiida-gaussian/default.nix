{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  ase,
  pymatgen,

  # See ../harmonwig/default.nix for why cclib is a defaulted argument and what
  # meta.broken below is protecting.  It bites harder here than anywhere else
  # in this repo: aiida_gaussian/parsers/gaussian.py imports cclib at module
  # scope, and that module backs the `gaussian.base` and `gaussian.advanced`
  # entry points — so without cclib the plugin does not merely lose a feature,
  # it fails to load at all.
  #
  # Unlike harmonwig, satisfying this needs *two* things in one package set:
  # cclib, which only ever exists on the `python3` that cclib's overlay
  # overrides, and aiida-core, which reaches every interpreter through
  # pythonPackagesExtensions.  A set carrying both is buildable — the package
  # set is a fixpoint, so a pythonPackagesExtensions member does see the
  # packageOverrides entries — but it means rebuilding aiida-core's closure
  # against the nixpkgs NixOS-QChem pins rather than ours.  ../../flake.nix
  # deliberately stops short of wiring that up; see the note there.
  cclib ? null,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-gaussian";
  version = "2.2.0-unstable-2026-02-21";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "nanotech-empa";
    repo = "aiida-gaussian";
    rev = "8199876c8abbb2e83167d1c4e5ed4793ca2d4fa2";
    hash = "sha256-nkybyqpPuv4tl7apEHwdHNYlMgQxrxbLPkXAKx3nQrk=";
  };

  build-system = [ setuptools ];

  # aiida-core here is 2.10.0.dev0, and a pre-release does not satisfy
  # `aiida-core>=2.0.0,<3.0.0` under PEP 440 without an explicit opt-in.  Every
  # plugin in this repo needs this for the same reason.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    ase
    pymatgen
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py sets `pytest_plugins = ["aiida.manage.tests.pytest_fixtures"]`,
    # the deprecated module, which builds its profile from config_psql_dos({})
    # and therefore wants a real PostgreSQL.  pgtest supplies a throwaway
    # cluster; see ../pgtest for why postgresql has to be listed alongside it.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # No Gaussian binary is needed, and could not be provided if it were —
  # Gaussian is proprietary.  tests/calculations/ build their code node against
  # `/bin/true` and assert only on the generated input file, and
  # tests/parsers/ replay the stored outputs under tests/parsers/fixtures/.
  pythonImportsCheck = [
    "aiida_gaussian"
    "aiida_gaussian.calculations"
    "aiida_gaussian.parsers"
    "aiida_gaussian.workchains"
  ];

  meta = {
    description = "AiiDA plugin for the Gaussian quantum chemistry program";
    homepage = "https://github.com/nanotech-empa/aiida-gaussian";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through a package set that carries cclib; see above.
    broken = cclib == null;
  };
}
