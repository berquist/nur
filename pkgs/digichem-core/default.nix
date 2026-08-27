{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  adjusttext,
  basis-set-exchange,
  colour-science,
  configurables,
  deepmerge,
  dill,
  matplotlib,
  openprattle,
  periodictable,
  pillow,
  pyyaml,
  rdkit,
  scipy,

  # See ../harmonwig/default.nix for why cclib is a defaulted argument and what
  # meta.broken below is protecting.  digichem is a result-parsing library
  # built on top of cclib — digichem/parse/ is a set of cclib wrappers — so
  # there is no useful subset of it without one.
  cclib ? null,

  # tests
  pytestCheckHook,
  pytest-lazy-fixture,
  pyscf,
}:

buildPythonPackage {
  # The distribution is `digichem-core`; the repository is `digichem-library`
  # and the import name is `digichem`.
  pname = "digichem-core";
  version = "7.4.2-unstable-2026-05-08";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Chemicus-Ltd";
    repo = "digichem-library";
    rev = "2145e55d1d2f41d9b3a1f2679a9820d0cf0f0a77";
    hash = "sha256-TZ8GjUAtBK3icvd1bhJXRvpxWP1LZKkfi1I6+B9FCyA=";
  };

  build-system = [ hatchling ];

  # `adjustText` in pyproject.toml; `adjusttext` is what nixpkgs calls the same
  # distribution, and the two normalise to the same name under PEP 503.
  dependencies = [
    adjusttext
    basis-set-exchange
    colour-science
    configurables
    deepmerge
    dill
    matplotlib
    openprattle
    periodictable
    pillow
    pyyaml
    rdkit
    scipy
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [
    pytestCheckHook
    pytest-lazy-fixture
    pyscf
  ];

  # No quantum chemistry program is needed.  digichem/test/ replays stored
  # Gaussian and Turbomole outputs through the parsers and asserts on the
  # energies; pyscf is the one real calculation, and it is a library.
  pythonImportsCheck = [
    "digichem"
    "digichem.parse"
    "digichem.result"
    "digichem.config"
  ];

  meta = {
    description = "Open-source library for Digichem core components — computational chemistry result parsing and reporting";
    homepage = "https://github.com/Chemicus-Ltd/digichem-library";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through the flake; see the cclib argument above.
    broken = cclib == null;
  };
}
