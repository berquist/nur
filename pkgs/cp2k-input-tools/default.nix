{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  poetry-core,

  # dependencies
  click,
  jinja2,
  pint,
  pydantic,
  transitions,

  # optional-dependencies
  pygls,
  ruamel-yaml,

  # tests
  pytestCheckHook,
  lsprotocol,
  pytest-console-scripts,
}:

buildPythonPackage rec {
  pname = "cp2k-input-tools";
  version = "0.9.1";
  pyproject = true;

  # ../aiida-gaussian-datatypes asks for `>= 0.8.0` and imports
  # cp2k_input_tools.basissets and .pseudopotentials, both of which this tag
  # still has.  Unrelated to ../cp2k-output-tools despite the shared author and
  # naming — different repository, different modules.
  src = fetchFromGitHub {
    owner = "cp2k";
    repo = "cp2k-input-tools";
    tag = "v${version}";
    hash = "sha256-GJ/C3mVRakeU6d8dsIII6p/sNkXiRep/z6mfl089PkM=";
  };

  build-system = [ poetry-core ];

  # As in ../cp2k-output-tools: upstream still names the pre-1.1 backend from
  # the full `poetry` application, which nixpkgs does not expose as a Python
  # module.  poetry-core has carried the same entry points under
  # `poetry.core.masonry.api` since 1.0.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["poetry>=1"]' 'requires = ["poetry-core>=1"]' \
      --replace-fail 'build-backend = "poetry.masonry.api"' \
                     'build-backend = "poetry.core.masonry.api"'
  '';

  # `Pint = ">=0.15,<0.24"` and `transitions = ">=0.7,<0.10"` are upper bounds
  # from 2023 that nixpkgs' versions exceed; nothing in the source uses an API
  # either project has since changed.
  pythonRelaxDeps = [
    "Pint"
    "transitions"
  ];

  dependencies = [
    click
    jinja2
    pint
    pydantic
    transitions
  ];

  optional-dependencies = {
    lsp = [ pygls ];
    yaml = [ ruamel-yaml ];
  };

  # tests/conftest.py imports pygls unconditionally, so the lsp extra is needed
  # for the suite to collect at all rather than only for test_lsp.py; lsprotocol
  # supplies the message types that test exchanges.  ruamel.yaml is the yaml
  # extra, exercised by test_cli.py and test_generator.py, and the four files
  # that drive the console scripts need pytest-console-scripts for the
  # `script_runner` fixture.
  nativeCheckInputs = [
    pytestCheckHook
    lsprotocol
    pytest-console-scripts
  ]
  ++ optional-dependencies.lsp
  ++ optional-dependencies.yaml;

  # Those files force `script_launch_mode("subprocess")`, so the console
  # scripts have to be findable as real programs; see ../cp2k-output-tools,
  # where leaving this out failed six tests with FileNotFoundError.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  pythonImportsCheck = [
    "cp2k_input_tools"
    "cp2k_input_tools.basissets"
    "cp2k_input_tools.pseudopotentials"
  ];

  meta = {
    description = "Python tools to handle CP2K input files";
    homepage = "https://github.com/cp2k/cp2k-input-tools";
    changelog = "https://github.com/cp2k/cp2k-input-tools/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "cp2klint";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
