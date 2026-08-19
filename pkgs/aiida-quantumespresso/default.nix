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
  which,
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

    # tools/setup.py's `get_executable_paths` runs
    # `. /dev/stdin > /dev/null && which <exe>` over the transport, so the eight
    # tests in tests/tools/test_code_setup.py need the program.  Three of them
    # look for a pw.x the fixture just created and get "which: command not
    # found" instead; the other five are the negative cases, and they fail on
    # the message rather than on the outcome — they assert the text "the `which`
    # command returned an empty output", which is the branch a *present* which
    # takes when it finds nothing.  See ../aiida-octopus for the same argument.
    which
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # tests/cli/test_commands.py walks the click group and runs every subcommand
  # as `subprocess.run(['aiida-quantumespresso', ..., '--help'])`, twice over
  # for the two spellings of the flag — 48 parametrizations, all of which fail
  # with FileNotFoundError naming the program.  See ../aiida-pseudo/default.nix,
  # which has the identical test and the identical reason: a package's own
  # $out/bin is never added to PATH, because a package is not a build input of
  # itself.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  # aiida-core has been on `main` since ../aiida-core needed the ZeroMQ broker,
  # and pytest-regressions references recorded against a release do not always
  # survive that.  This is the one that does not.
  #
  # `BandsData.set_kpointsdata` copies `pbc` off the KpointsData it is given,
  # and until aiida-core#6990 (the pydantic model rework, May 2026) the
  # `KpointsData.pbc` getter read the three attributes with no default.  It now
  # reads them with `False`, so a KpointsData that never had a cell — which is
  # what the matdyn parser builds — yields (False, False, False) instead, and
  # the setter writes all three onto the BandsData:
  #
  #     @@ -10,4 +10,7 @@
  #        labels: []
  #     +  pbc1: false
  #     +  pbc2: false
  #     +  pbc3: false
  #        units: THz
  #
  # The parser is unchanged and the three values are aiida-core's own documented
  # default, so the recorded file is what is stale.  Adding the keys is the fix;
  # `--force-regen` is not, since it would rewrite every reference in the suite
  # and hide any of them that had drifted for a real reason.
  postPatch = ''
    substituteInPlace tests/parsers/test_matdyn/test_matdyn_default.yml \
      --replace-fail \
        "  labels: []
      units: THz" \
        "  labels: []
      pbc1: false
      pbc2: false
      pbc3: false
      units: THz"
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
