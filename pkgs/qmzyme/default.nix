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
  openbabel,

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
  #
  # The `~=2.0` pin beside it has to go too.  nixpkgs carries versioningit 3.3.0,
  # and a build-system requirement is checked before anything else runs, so the
  # build stops at "Unmet dependencies ... wanted: ~=2.0, found: 3.3.0" — this is
  # `[build-system] requires`, which pythonRelaxDeps does not reach; it rewrites
  # the built distribution's runtime metadata.  Nothing here uses an API
  # versioningit changed in 3.0: the only thing this project asks of it is the
  # `default-version` fallback rewritten on the line above.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'default-version = "0.0.0"' 'default-version = "${version}"' \
      --replace-fail '"versioningit~=2.0"' '"versioningit"'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # `openbabel>=3.2.0` is never imported — a grep for openbabel or pybel across
  # the whole source tree returns nothing — so there is no Python distribution
  # for pythonRuntimeDepsCheckHook to find, and the requirement has to go.
  #
  # It does not follow that Open Babel is unused, and an earlier version of this
  # comment drew exactly that wrong conclusion.  QMzyme shells out to the
  # *program*: QMzyme/aqme/qprep.py — a vendored copy of AQME — reaches
  # `model.write_input()` and runs
  #
  #     subprocess.run(["obabel", "-ipdb", "…", "-osdf", "-O…"])
  #
  # resolved from PATH.  Six tests failed on `FileNotFoundError: 'obabel'` once
  # the rdkit metadata fix let the suite run at all.  ../../overlays supplies it
  # through nativeCheckInputs below.
  #
  # Nothing wraps it in for a consumer, because there is nothing to wrap:
  # qmzyme ships no console scripts, so `obabel` has to be on PATH in whatever
  # environment calls write_input().  That is upstream's design, not ours.
  pythonRemoveDeps = [ "openbabel" ];

  dependencies = [
    mdanalysis
    pandas
    pyyaml
    rdkit
  ];

  # openbabel is unconditional, unlike cclib and unlike aqme's xtb and crest:
  # it is a plain top-level nixpkgs attribute on every package set this is
  # built against, so there is no absence to fall back from and no tests to
  # skip.  See the pythonRemoveDeps note above for what wants it.
  nativeCheckInputs = [
    pytestCheckHook
    openbabel
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
