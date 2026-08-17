{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  aiida-core,
  aiida-pseudo,
  click,
  importlib-resources,
  jsonschema,
  numpy,
  packaging,
  pydantic,
  qe-tools,
  xmlschema,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pgtest,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-quantumespresso";
  version = "5.0.0";
  pyproject = true;

  # fetchFromGitHub rather than fetchPypi even though 5.0.0 is released, for a
  # sharper reason than aiida-cp2k's: pyproject.toml's
  # [tool.hatch.build.targets.sdist] excludes 'tests/' outright, so the sdist
  # cannot run its own suite.  The tag is the same tree as the release.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-quantumespresso";
    tag = "v${version}";
    hash = "sha256-j2p8S8+sCIVO/7bRoSx0NxXRE8gSahYVfkrn8CS7Q6Y=";
  };

  build-system = [ hatchling ];

  # aiida-core because 2.10.0.dev0 is a pre-release and does not satisfy
  # `aiida_core[atomic_tools]~=2.8` without an opt-in.
  #
  # xmlschema because upstream pins `~=2.0` and the locked nixpkgs has 4.3.1.
  # This is the one relaxation in this repo that crosses two majors of a library
  # the package really uses: parsers/parse_xml/parse.py and
  # tools/calculations/pw.py both build an `XMLSchema` and validate pw.x output
  # against it.  If this package fails, that is the first place to look, and the
  # answer would be packaging xmlschema 2.x alongside rather than widening the
  # pin further.
  pythonRelaxDeps = [
    "aiida-core"
    "xmlschema"
  ];

  dependencies = [
    aiida-core
    aiida-pseudo
    click
    importlib-resources
    jsonschema
    numpy
    packaging
    pydantic
    qe-tools
    xmlschema
  ]
  # Upstream asks for `aiida_core[atomic_tools]`, not bare aiida-core: the
  # parsers reach for ase, pymatgen and seekpath.  See ../aiida-core for what is
  # in that extra and why it exists there at all.
  ++ aiida-core.optional-dependencies.atomic_tools;

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions

    # tests/conftest.py names `aiida.tools.pytest_fixtures`, the modern module,
    # which defaults to core.sqlite_dos with no broker and needs no services at
    # all.  pgtest and postgresql are here only because upstream's `tests` extra
    # lists pgtest, so a fixture that opts into the psql profile can find it.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # No Quantum ESPRESSO binary is needed: codes come from `aiida_code_installed`
  # pointed at /bin/bash, and every parser test replays stored pw.x output from
  # tests/parsers/fixtures/.

  pythonImportsCheck = [
    "aiida_quantumespresso"
    "aiida_quantumespresso.calculations.pw"
    "aiida_quantumespresso.parsers.pw"
    "aiida_quantumespresso.workflows.pw.base"
  ];

  meta = {
    description = "Official AiiDA plugin for Quantum ESPRESSO";
    homepage = "https://github.com/aiidateam/aiida-quantumespresso";
    changelog = "https://github.com/aiidateam/aiida-quantumespresso/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "aiida-quantumespresso";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
