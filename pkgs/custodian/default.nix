{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  monty,
  psutil,
  ruamel-yaml,

  # tests
  pytestCheckHook,
  pymatgen,
}:

buildPythonPackage rec {
  pname = "custodian";
  version = "2025.12.14-unstable-2026-08-03";
  pyproject = true;

  # A commit rather than the v2025.12.14 tag: the tag is eight months behind
  # HEAD, and quacc's `custodian>=2025.12.14` is satisfied either way.  The
  # sdist would also do — tests/ is shipped — but a git pin keeps this
  # consistent with the rest of the tree and with `nix-update`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "custodian";
    rev = "bb78390b4a9560d7268bc88455a1b8f3f72fef95";
    hash = "sha256-v5CjuqOkSvr9x/fY7tk10dAOgDAiMShYY4ANAMr71oE=";
  };

  build-system = [ setuptools ];

  dependencies = [
    monty
    psutil
    ruamel-yaml
  ];

  # pymatgen is a *test* dependency only — upstream keeps it out of
  # `dependencies` and offers it as the `matsci` extra, because the core
  # error-handling machinery does not import it.  Seven of the twenty-one test
  # modules do (vasp, qchem, cp2k, feff), so leaving it out would quietly
  # reduce the suite to the two top-level modules.
  #
  # It needs the interpreter gate lifted — nixpkgs marks pymatgen
  # `disabled = pythonAtLeast "3.13"`, so on this repo's 3.13 pin the attribute
  # throws rather than builds.  That fix is shared with the aiida overlay; see
  # the `pymatgenFor` binding in ../../overlays/default.nix.
  nativeCheckInputs = [
    pytestCheckHook
    pymatgen
  ];

  pythonImportsCheck = [
    "custodian"
    "custodian.custodian"
  ];

  meta = {
    description = "Just-in-time job management and error correction for scientific calculations";
    homepage = "https://github.com/materialsproject/custodian";
    changelog = "https://github.com/materialsproject/custodian/blob/master/docs/changelog.md";
    license = lib.licenses.mit;
    mainProgram = "cstdn";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
