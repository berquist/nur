{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  pydantic,
  rich,
}:

buildPythonPackage rec {
  pname = "aiida-submission-controller";
  version = "0.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-submission-controller";
    tag = "v${version}";
    hash = "sha256-/bF7pkz/AmLfn+jyqUdEuuuoVGMrMa/jvy5y45lufN8=";
  };

  build-system = [ flit-core ];

  # See ../aiida-orca/default.nix: aiida-core here is a pre-release, which does
  # not satisfy `aiida-core>=2.5` under PEP 440 without an opt-in.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    pydantic
    rich
  ];

  # `import aiida_submission_controller` reaches aiida-core, which creates its
  # configuration directory on import — under $HOME, and a Nix builder's $HOME
  # is /homeless-shelter, which does not exist and cannot be created:
  #
  #   aiida.common.exceptions.ConfigurationError: could not create the
  #   `/homeless-shelter/.aiida` configuration directory:
  #   [Errno 13] Permission denied: '/homeless-shelter'
  #
  # preBuild rather than preCheck even though there is no check phase to speak
  # of: pythonImportsCheck runs after the install, and preBuild is the hook that
  # is set by then.  See ../aiida-core/default.nix.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # Upstream ships no test suite at all — not a suite excluded from the sdist,
  # which is the usual case here (see the sdist-has-no-tests trap in
  # ../../AGENTS.md), but no `tests/` directory in the repository.  So there is
  # nothing for pytestCheckHook to run and the import check is the whole check.
  #
  # Both submodules are worth naming: the package's entire surface is the two
  # controller classes, and each pulls in a different part of aiida-core.
  pythonImportsCheck = [
    "aiida_submission_controller"
    "aiida_submission_controller.from_group"
    "aiida_submission_controller.base"
  ];

  meta = {
    description = "Controllers to submit AiiDA processes in batches, keeping a fixed number running";
    homepage = "https://github.com/aiidateam/aiida-submission-controller";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
