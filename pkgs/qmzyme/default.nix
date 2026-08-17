{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  mdanalysis,
  pandas,
  pyyaml,
  rdkit,

  # tests
  pytestCheckHook,

  # cclib arrives from a flake input and is absent on the bare NUR path; see
  # ../harmonwig/default.nix for the mechanism.  Unlike harmonwig this package
  # does not become unbuildable without it — QMzyme/SelectionSchemes.py imports
  # cclib inside select_atoms(), not at module scope, and upstream's own
  # pyproject.toml keeps it out of `dependencies` and in the `test` extra for
  # exactly that reason.  So no meta.broken here; one test is skipped instead.
  cclib ? null,
}:

buildPythonPackage rec {
  pname = "qmzyme";
  version = "0.1.2.dev20260605";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Klem-Research-Group";
    repo = "QMzyme";
    rev = "c388e23d3a9d3e372cfc31c8000b83ce35b5a656";
    hash = "sha256-HNSVsj7yW+UB8lwb6fccrDaBUxaUdcJopmujO1EYV8o=";
  };

  # See ../mda-xdrlib for why the versioningit fallback has to be rewritten.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'default-version = "0.0.0"' 'default-version = "${version}"'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # `openbabel>=3.2.0` is declared but never imported: a grep for openbabel or
  # pybel across the whole source tree returns nothing.  Its comment in
  # pyproject.toml ("used to write various chemical structure files formats")
  # describes an intention, and leaving the requirement in place would make
  # pythonRuntimeDepsCheckHook demand a distribution nothing uses.
  pythonRemoveDeps = [ "openbabel" ];

  dependencies = [
    mdanalysis
    pandas
    pyyaml
    rdkit
  ];

  nativeCheckInputs = [
    pytestCheckHook
  ]
  ++ lib.optional (cclib != null) cclib;

  # tests/test_SelectionSchemes.py::test_ChargeShiftAnalysis is the one case
  # that reaches ChargeShiftAnalysis.select_atoms(), and so the one that needs
  # cclib.  Everything else in the suite runs unchanged.
  disabledTests = lib.optional (cclib == null) "test_ChargeShiftAnalysis";

  pythonImportsCheck = [
    "QMzyme"
    "QMzyme.GenerateModel"
    "QMzyme.RegionBuilder"
    "QMzyme.SelectionSchemes"
  ];

  meta = {
    description = "QM-based enzyme model generation and validation";
    homepage = "https://github.com/Klem-Research-Group/QMzyme";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
