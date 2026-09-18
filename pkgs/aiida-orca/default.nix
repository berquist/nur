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
  bash,
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

  # A patch file rather than `postPatch`: the fixtures below need their own
  # exact indentation (a literal tab in the .in file, two- and four-space
  # nesting in the .yml files) preserved byte for byte, and Nix computes an
  # indented string's dedent over the whole `postPatch` literal -- see
  # ../pymatgen/default.nix for what that quietly does to a replacement that
  # has to keep its own indentation, and ../aiida-workgraph's
  # await-daemon-adoption.patch for the same call made the same way.
  patches = [ ./regen-stale-fixtures.patch ];

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

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # `aiida_local_code_factory('orca.orca', '/bin/bash')` in tests/conftest.py
  # asks for an executable a Nix build sandbox does not have — it provides
  # /bin/sh and nothing else.  See ../aiida-core/default.nix for the long form
  # of why that surfaces as a parse failure rather than as "no such file".
  #
  # patchPhase rather than postBuild: the file is source, the change is
  # unconditional, and postBuild runs late enough that only the check phase
  # would ever have seen it.
  postPatch = ''
    # See ../aiida-cp2k for why this is a rewrite rather than a version bump,
    # and why pgtest, postgresql and the locale export left with it.
    # The dropped fixtures too; see ../aiida-diff.  These run before the
    # /bin/bash rewrite below on purpose — that one would otherwise have already
    # changed the argument this matches on.  `recursive_merge` is safe: this
    # conftest defines its own, it never came from the plugin.
    substituteInPlace tests/conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def generate_inputs_orca(aiida_local_code_factory, generate_structure):' \
        'def generate_inputs_orca(aiida_code_installed, generate_structure):' \
      --replace-fail \
        "aiida_local_code_factory('orca.orca', '/bin/bash')" \
        "aiida_code_installed(default_calc_job_plugin='orca.orca', filepath_executable='/bin/bash')"
    substituteInPlace examples/conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def orca_code(aiida_local_code_factory):' \
        'def orca_code(aiida_code_installed):' \
      --replace-fail \
        "aiida_local_code_factory('orca', 'orca')" \
        "aiida_code_installed(default_calc_job_plugin='orca', filepath_executable='orca')"

    substituteInPlace tests/conftest.py \
      --replace-fail "/bin/bash" "${bash}/bin/bash"
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
