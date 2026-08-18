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
  ruamel-yaml,

  # tests
  pytestCheckHook,
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
  #
  # The language-server half of this project cannot be built against the pygls
  # in nixpkgs.  Upstream asks for `pygls = "^1.0.0"` — still, on master — and
  # nixpkgs carries 2.1.1, where `pygls.server.LanguageServer` has moved and the
  # decorator API around it changed.  Supplying it anyway fails at *collection*
  # rather than in one test, for two reasons, and both have to be undone:
  #
  #   1. tests/conftest.py imports LanguageServer in a class body, so the import
  #      runs when conftest is loaded.  It becomes a None default for the `LS`
  #      argument below it, which only ClientServer.__init__ ever reads.
  #   2. That `client_server` fixture is `autouse=True`, so pytest would start a
  #      language server for every test in the suite rather than for the four in
  #      tests/test_lsp.py that ask for it.  Those four request it by name
  #      through ClientServer.decorate(), so dropping autouse costs nothing.
  #
  # tests/test_lsp.py is then the only casualty, and is disabled below.  The
  # `lsp` extra is not declared at all: an extra whose sole member cannot
  # satisfy the code that imports it is worse than none, since it would install
  # cleanly and fail at runtime.  ../aiida-gaussian-datatypes, the one consumer
  # here, uses only the basis-set and pseudopotential parsers.
  #
  # The `cp2k-language-server` entry point goes with it.  Six of the seven
  # console scripts work; that one imports cp2k_input_tools.ls, which imports
  # pygls, so leaving it installed would put a program in $out/bin that can only
  # ever raise ImportError.
  #
  # `fromcp2k` is broken on Python 3.11 and later, and this is a real defect
  # rather than a test artefact — the program rejects its own default argument
  # with "Invalid value for '-t' / '--trafo': 'auto' is not one of .", an empty
  # choice list.  Its `Trafos` enum wraps three functions in `functools.partial`
  # to stop Enum treating them as methods, which is what the linked
  # StackOverflow answer above them recommends.  That trick stopped working when
  # partial objects became descriptors: Enum now skips them for the same reason
  # it skips a plain function, so the class has no members and
  # `[t.name for t in Trafos]` is empty.  CPython emits a FutureWarning at that
  # class body naming `enum.member()` as the replacement, which is what this
  # applies; it says what the partial wrapper was trying to say.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["poetry>=1"]' 'requires = ["poetry-core>=1"]' \
      --replace-fail 'build-backend = "poetry.masonry.api"' \
                     'build-backend = "poetry.core.masonry.api"' \
      --replace-fail "cp2k-language-server = 'cp2k_input_tools.cli.lsp:cp2k_language_server'" ""

    substituteInPlace tests/conftest.py \
      --replace-fail '    from pygls.server import LanguageServer' '    LanguageServer = None' \
      --replace-fail '@pytest.fixture(autouse=True)' '@pytest.fixture'

    substituteInPlace cp2k_input_tools/cli/fromcp2k.py \
      --replace-fail 'from enum import Enum' 'from enum import Enum, member' \
      --replace-fail 'auto = functools.partial(_key_trafo)' \
                     'auto = member(functools.partial(_key_trafo))' \
      --replace-fail 'lower = functools.partial(str.lower)' \
                     'lower = member(functools.partial(str.lower))' \
      --replace-fail 'upper = functools.partial(str.upper)' \
                     'upper = member(functools.partial(str.upper))'
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
    yaml = [ ruamel-yaml ];
  };

  # ruamel.yaml is the yaml extra, exercised by test_cli.py and
  # test_generator.py; the four files that drive the console scripts need
  # pytest-console-scripts for the `script_runner` fixture.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-console-scripts
  ]
  ++ optional-dependencies.yaml;

  disabledTestPaths = [ "tests/test_lsp.py" ];

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
