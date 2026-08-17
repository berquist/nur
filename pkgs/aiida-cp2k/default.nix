{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-gaussian-datatypes,
  aiida-pseudo,
  ase,
  cp2k-output-tools,
  ruamel-yaml,
  upf-to-json,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  cp2k,
}:

buildPythonPackage rec {
  pname = "aiida-cp2k";
  version = "2.1.1";
  pyproject = true;

  # fetchFromGitHub rather than fetchPypi even though 2.1.1 is released, because
  # examples/ is what supplies this package's test data — the basis set and
  # pseudopotential files the DFT example reads — and aiida-cp2k's pyproject.toml
  # has no [tool.flit.sdist] section pinning what the sdist carries.  The tag is
  # the same commit either way.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-cp2k";
    tag = "v${version}";
    hash = "sha256-UjcZj5apv0nuLctNYoTzRK9SFo1xhVr0Mfehaf5P7FE=";
  };

  build-system = [ flit-core ];

  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    aiida-gaussian-datatypes
    aiida-pseudo
    ase
    cp2k-output-tools
    ruamel-yaml
    upf-to-json
  ];

  # Two things in conftest.py are written for upstream's Docker image and
  # cannot work anywhere else.
  #
  # The first is a session-scoped autouse fixture that shells out to
  # `aiida-pseudo install sssp`, which downloads from Materials Cloud.  Nothing
  # under test/ actually uses an SSSP family — the fixture is there for the
  # examples, which are not collected here — so the download is removed rather
  # than replaced by a packaged archive that would then go unused.  If the
  # examples are ever brought into checkPhase, this is where an offline
  # `aiida-pseudo install family <archive>` would go instead.
  #
  # The second is a code fixture hardcoding /opt/conda/envs/cp2k/bin/cp2k.psmp
  # and a `conda activate`.  Pointed at the real binary, it works.
  # `$(` and `\n` below are literal in a Nix indented string — only `${` would
  # need escaping — so these match the Python source exactly as written.
  postPatch = ''
    substituteInPlace conftest.py \
      --replace-fail 'executable="/opt/conda/envs/cp2k/bin/cp2k.psmp"' \
                     'executable="${cp2k}/bin/cp2k.psmp"' \
      --replace-fail 'eval "$(command conda shell.bash hook 2> /dev/null)"\nconda activate cp2k\n' \
                     "" \
      --replace-fail 'subprocess.run(' 'list('
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
    cp2k
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # `test`, singular, is the unit-test directory.  Restricting to it is a
  # scoping decision rather than a way of skipping something: upstream sets
  # `python_files = "test_*.py example_*.py"` with no `testpaths`, so a bare run
  # also collects examples/, and those submit real CP2K jobs through a running
  # AiiDA daemon.  A checkPhase has no daemon and no broker.  Those examples are
  # covered instead by the plugin-cp2k VM test in ../../tests/aiida/vm.nix,
  # where a daemon does exist.
  pytestFlags = [ "test" ];

  pythonImportsCheck = [
    "aiida_cp2k"
    "aiida_cp2k.calculations"
    "aiida_cp2k.parsers"
    "aiida_cp2k.workchains"
  ];

  meta = {
    description = "AiiDA plugin for the CP2K electronic structure code";
    homepage = "https://github.com/aiidateam/aiida-cp2k";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
