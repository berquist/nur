{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  click,
  pint,
  pydantic,
  requests,

  # tests
  pytestCheckHook,
  numpy,
  pgtest,
  postgresql,
}:

buildPythonPackage rec {
  pname = "aiida-pseudo";
  version = "1.7.2";
  pyproject = true;

  # The lower bound aiida-quantumespresso pins (`>=1.7.2,<2`); aiida-cp2k asks
  # for `~=1.2`, which this satisfies.
  #
  # From git rather than PyPI so that `tests/` is present at all — the sdist
  # excludes it, as with ../kiwipy and ../plumpy.  Here that only makes the
  # situation legible rather than fixing it; see the checkPhase note below.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-pseudo";
    tag = "v${version}";
    hash = "sha256-DkEQ3sVMaKjES2U6oha6FdjgPGFLM80tyPIgEH7hR1U=";
  };

  build-system = [ flit-core ];

  # aiida-core here is a 2.10.0.dev0 snapshot, and a pre-release does not
  # satisfy a `>=2.x` specifier under PEP 440 unless pre-releases are opted in.
  # Every AiiDA plugin in this repo needs this for the same reason.
  pythonRelaxDeps = [
    "aiida-core"
    "click"
    "pint"
  ];

  dependencies = [
    aiida-core
    click
    pint
    pydantic
    requests
  ];

  # tests/conftest.py sets `pytest_plugins = 'aiida.tools.pytest_fixtures'`, so
  # the suite needs a working AiiDA profile — hence pgtest and postgresql, as
  # in ../aiida-core.  numpy is imported directly by the family tests.
  nativeCheckInputs = [
    pytestCheckHook
    numpy
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix: importing aiida creates $HOME/.aiida, and
  # /homeless-shelter does not exist.  genericBuild runs every phase in one
  # shell, so this covers pythonImportsCheck as well as checkPhase.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # tests/cli/test_root.py walks every subcommand of the click group and runs
  # `subprocess.run(['aiida-pseudo', ..., '--help'])` for each — twice, once per
  # spelling of the help flag.  Its docstring says the subprocess is on purpose:
  # click's Context.invoke skips the parent commands and so misses their
  # initialisation, which is the part being tested.
  #
  # That needs the console script on PATH, and nothing puts it there.
  # pytestCheckPhase runs from preDistPhases, after the wheel is installed, so
  # $out/bin exists by then; but $out is not a build input of itself, and a
  # package's own bin directory is never added.  All twenty parametrizations
  # fail with FileNotFoundError naming the program, which reads like a missing
  # dependency rather than the missing PATH entry it is.
  #
  # The script needs no wrapper: its shebang is the same interpreter pytest is
  # running under, and python-setup-hook.sh has already put every host-offset
  # input's site-packages on PYTHONPATH, so the subprocess inherits the imports.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  # `aiida-pseudo install <family>` downloads pseudopotential archives from
  # Materials Cloud and the SSSP/PseudoDojo publishers.  Those tests are the
  # network-bound ones; the parsing, family and CLI tests below are not.
  disabledTests = [
    "test_install_sssp"
    "test_install_pseudo_dojo"
    "test_download_sssp"
    "test_download_pseudo_dojo"
  ];

  pythonImportsCheck = [
    "aiida_pseudo"
    "aiida_pseudo.data.pseudo"
    "aiida_pseudo.groups.family"
  ];

  meta = {
    description = "AiiDA plugin for managing pseudopotentials";
    homepage = "https://github.com/aiidateam/aiida-pseudo";
    license = lib.licenses.mit;
    mainProgram = "aiida-pseudo";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
