{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  aiida-core,
  ase,
  periodictable,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
  bash,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-orca";
  version = "1.0.0-unstable-2026-08-16";
  pyproject = true;

  # The newest tag is v0.7.0 but `__version__` on this branch is already 1.0.0,
  # and only this branch has the ORCA 6 output format the parser tests cover.
  # Taking the tag would package a parser that cannot read current ORCA output.
  #
  # `ezpzbz`, not the `pzarabadip` in pyproject.toml's Home URL: the two are the
  # same person, and this is the account the repository is actually served from.
  src = fetchFromGitHub {
    owner = "ezpzbz";
    repo = "aiida-orca";
    rev = "90e9a3b27de0f9767e89ee8903728fabf126b49c";
    hash = "sha256-EQhOjFTbrFPV3gMBkJUO1dLXkZZ698pXNe7jff7lYyQ=";
  };

  build-system = [ hatchling ];

  # aiida-core here is 2.10.0.dev0, and a pre-release does not satisfy
  # `aiida-core>=2.1,<3` under PEP 440 without an explicit opt-in.  Every plugin
  # in this repo needs this for the same reason.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    ase
    periodictable
  ];

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, which builds its profile from config_psql_dos({}) and
    # therefore wants a real PostgreSQL.  pgtest supplies a throwaway cluster;
    # see ../pgtest for why postgresql has to be listed alongside it.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  postBuild = ''
    substituteInPlace tests/conftest.py \
      --replace-fail "/bin/bash" "/${bash}/bin/bash"
  '';

  # No ORCA binary is needed: the calculation tests build their code node with
  # `aiida_local_code_factory('orca.orca', '/bin/bash')` and only assert on the
  # generated input file, and the parser tests replay the stored outputs under
  # tests/parsers/fixtures/.  examples/ carries its own pytest.ini and sits
  # outside `testpaths`, so it is not collected.
  #
  # cclib is not a dependency: aiida_orca/parsers/cclib/ is a vendored subset.
  pythonImportsCheck = [
    "aiida_orca"
    "aiida_orca.calculations"
    "aiida_orca.parsers"
    "aiida_orca.workchains"
  ];

  meta = {
    description = "AiiDA plugin for the ORCA quantum chemistry program";
    homepage = "https://github.com/ezpzbz/aiida-orca";
    changelog = "https://github.com/ezpzbz/aiida-orca/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
