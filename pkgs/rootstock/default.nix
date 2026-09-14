{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,
  uv-dynamic-versioning,

  # dependencies
  ase,
  numpy,
  packaging,
  tomli-w,

  # tests
  pytestCheckHook,
}:

# rootstock — runs MLIP calculators (mace, orb, pet, deepmd…) each in its own
# isolated Python environment, so their conflicting dependency pins never have
# to be resolved together.  Carried for `quacc[mlip]`.
buildPythonPackage (finalAttrs: {
  pname = "rootstock";
  version = "1.6.4-unstable-2026-09-11";
  pyproject = true;
  __structuredAttrs = true;

  # The project moved from `Quantum-Accelerators` to `Garden-AI`, and GitHub
  # does not redirect codeload for it: the old owner's archive URL answers 404,
  # which is what broke this build rather than anything in the source.  A
  # renamed owner is a `rev` that still resolves in a local clone while being
  # unfetchable, so the 404 is the only symptom — check the owner before
  # suspecting a force-push.
  src = fetchFromGitHub {
    owner = "Garden-AI";
    repo = "rootstock";
    rev = "9700aa4089492c0eb401ce065c8fe5c35bc6a91b";
    hash = "sha256-ACTcBw/vfSJcBxPzrYEv/gtecGBSmWLalI5vl2us/m8=";
  };

  # `uv-dynamic-versioning` reads the version from git, which fetchFromGitHub
  # does not provide, so it would fall back to `fallback-version = "0.0.0"`.
  # The bypass env var is what it checks first.
  env.UV_DYNAMIC_VERSIONING_BYPASS = lib.head (lib.splitString "-" finalAttrs.version);

  # ...and nixpkgs' uv-dynamic-versioning carries a setup hook that exports the
  # same variable from `$version` in `preBuildHooks`, which runs after `env` is
  # in place and therefore wins.  `$version` here is `1.6.4-unstable-<date>`,
  # which PEP 440 rejects, so hatchling aborts with "Invalid version ... from
  # source `uv-dynamic-versioning`" before a wheel is built.
  #
  # The hook guards itself on this exact name for this exact case.  Setting it
  # is what lets the `env` above be the value that reaches the build; without it
  # that line is dead, and the failure only shows on a package whose version is
  # not PEP 440 — which is every `-unstable-` one here.
  dontBypassUvDynamicVersioning = true;

  build-system = [
    hatchling
    uv-dynamic-versioning
  ];

  dependencies = [
    ase
    numpy
    packaging
    tomli-w
  ];

  # The suite is not run.  rootstock's job is to build isolated environments by
  # shelling out to `uv`, then download model weights into them — nearly every
  # one of its ~90 test modules needs `uv` on PATH, the network, or both, and
  # `tests/integrations/` needs atomate2.  `pythonImportsCheck` covers the API.
  doCheck = false;

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "rootstock"
    "rootstock.calculator"
  ];

  meta = {
    description = "MLIP calculators with isolated Python environments";
    homepage = "https://github.com/Garden-AI/rootstock";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
