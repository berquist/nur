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
  version = "1.6.4-unstable-2026-09-04";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "Quantum-Accelerators";
    repo = "rootstock";
    rev = "627d55b980e6ef11f37c181f70e382ad4130c60d";
    hash = "sha256-na54QLInbGZ6h7AycURcrlk52xOlpPQcxe0qftryDGs=";
  };

  # `uv-dynamic-versioning` reads the version from git, which fetchFromGitHub
  # does not provide, so it would fall back to `fallback-version = "0.0.0"`.
  # The bypass env var is what it checks first.
  env.UV_DYNAMIC_VERSIONING_BYPASS = lib.head (lib.splitString "-" finalAttrs.version);

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
    homepage = "https://github.com/Quantum-Accelerators/rootstock";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
