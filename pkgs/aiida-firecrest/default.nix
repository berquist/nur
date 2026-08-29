{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  click,
  pyfirecrest,
  pyyaml,
}:

buildPythonPackage rec {
  pname = "aiida-firecrest";
  version = "1.0.0-unstable-2026-08-11";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-firecrest";
    rev = "870f00e0809808215d5bb0516f017f6f4f0fe34f";
    hash = "sha256-6CnK//fomJTTXRXK2nUdzv98sT3iJdSQdDzvBm0Tl1g=";
  };

  build-system = [ flit-core ];

  # See ../aiida-orca/default.nix for the pre-release reason.  `pyfirecrest>=3.6.0`
  # is satisfied by the 3.9.0 in ../pyfirecrest.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    click
    pyfirecrest
    pyyaml
  ];

  # `import aiida_firecrest` reaches aiida-core, which creates its configuration
  # directory on import, and a Nix builder's $HOME is /homeless-shelter:
  #
  #   ConfigurationError: could not create the `/homeless-shelter/.aiida`
  #   configuration directory: [Errno 13] Permission denied
  #
  # preBuild rather than preCheck because with `doCheck = false` below there is
  # no check phase, and pythonImportsCheck runs after the install regardless.
  # See ../aiida-core/default.nix.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # The suite needs a FirecREST server, and not a mocked one.
  #
  # Every test takes the `firecrest_config` fixture, which opens
  # `.firecrest-demo-config.json` and connects a `firecrest.v2.Firecrest`
  # client to the URL inside it.  That file describes the server the README
  # tells you to start with `docker compose -f 'docker-compose.yml' up -d
  # --build` — a container image, several services, and OIDC token endpoints.
  # A Nix build sandbox has neither docker nor a network, so this is the case
  # ../../AGENTS.md reserves `doCheck = false` for: a dependency the sandbox
  # genuinely cannot host, rather than one nobody has packaged.
  #
  # There is nothing to salvage by deselecting instead — all four modules are
  # transport, scheduler, computer and calculation tests, and every one of them
  # goes through that fixture.  What is left is the import check, which is not
  # nothing here: `aiida_firecrest.transport` imports pyfirecrest's v2 client
  # at module scope, so it is what would catch pyfirecrest's own API drifting.
  doCheck = false;

  pythonImportsCheck = [
    "aiida_firecrest"
    "aiida_firecrest.transport"
    "aiida_firecrest.scheduler"
    "aiida_firecrest.utils"
  ];

  meta = {
    description = "AiiDA transport and scheduler plugins that run jobs through FirecREST";
    homepage = "https://github.com/aiidateam/aiida-firecrest";
    license = lib.licenses.mit;
    mainProgram = "aiida-firecrest-cli";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
