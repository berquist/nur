{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  matplotlib,
  numpy,
  typing-extensions,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "strainjedi";
  version = "1.1.0-unstable-2026-07-01";
  pyproject = true;

  # The distribution is `strainjedi` and the import name is `strainjedi`, but
  # the repository is `neudecker-group/jedi` — unrelated to the `jedi`
  # autocompletion library that nixpkgs carries under that name.
  #
  # A commit rather than v1.0.0: the tag is a year behind, and pyproject.toml on
  # this commit already declares 1.1.0.
  src = fetchFromGitHub {
    owner = "neudecker-group";
    repo = "jedi";
    rev = "ecb59e1bae65eb7664386489270c812665cd0c84";
    hash = "sha256-OFjxymjGM/XFbcHyQyT8DRkaj2PvoAP+lx5XxuP2soo=";
  };

  build-system = [ setuptools ];

  # Upstream's explicit package list omits `strainjedi.visualization`, so the
  # installed package cannot be imported at all:
  #
  #   File ".../strainjedi/jedi.py", line 12, in <module>
  #     from strainjedi.visualization import ColorMapper, MatplotlibVisualizer, VMDVisualizer
  #   ModuleNotFoundError: No module named 'strainjedi.visualization'
  #
  # `[tool.setuptools] packages` names only `strainjedi` and `strainjedi.io`,
  # and setuptools does not recurse into subpackages when the list is given
  # explicitly — so the third subpackage is simply left out of the wheel, while
  # `strainjedi/__init__.py` imports `jedi.py`, which imports it on line 12.
  # An editable install off a git checkout hides this, which is presumably how
  # it survives upstream.
  #
  # Adding the entry rather than switching to automatic discovery: the explicit
  # list is upstream's choice and there may be directories they mean to keep
  # out, so the smaller change is the safer one.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '    "strainjedi.io",' '    "strainjedi.io",
        "strainjedi.visualization",'
  '';

  dependencies = [
    ase
    matplotlib
    numpy
    typing-extensions
  ];

  # matplotlib is imported at build time — `strainjedi/__init__.py` pulls in
  # jedi.py, which pulls in the visualization subpackage — and it wants a
  # writable config directory.  Without this it falls back with
  #
  #   mkdir -p failed for path /homeless-shelter/.config/matplotlib
  #
  # and rebuilds its font cache into a temporary directory on every import.
  # Same treatment ../aiida-core gives it in preBuild, and set here rather than
  # in preCheck because pythonImportsCheckPhase hits it too.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  nativeCheckInputs = [ pytestCheckHook ];

  # tests/conftest.py does `from tests.resources import path_to_test_resources`,
  # so the suite is imported as the package `tests` and needs the source root on
  # sys.path.  tests/__init__.py and tests/resources/__init__.py both exist, so
  # pytest's rootdir insertion handles that on its own — no preCheck needed.
  #
  # test_jedi_unit.py calls matplotlib.use("agg") itself, so no display is
  # required and MPLBACKEND does not have to be set here.

  pythonImportsCheck = [
    "strainjedi"
    "strainjedi.jedi"
  ];

  meta = {
    description = "Judgement of Energy DIstribution: strain analysis of molecules and periodic systems";
    homepage = "https://github.com/neudecker-group/jedi";
    license = lib.licenses.mit;
    mainProgram = "strainjedi";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
