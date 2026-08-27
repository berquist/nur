{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  click,

  # tests
  pytestCheckHook,
  deepdiff,
}:

buildPythonPackage rec {
  pname = "upf-to-json";
  version = "1.0.0";
  pyproject = true;

  # fetchFromGitHub at 1.0.0, not fetchPypi at the 0.9.5 that aiida-core's
  # `upf_to_json~=0.9.2` resolves to, and for one reason: **0.9.x ships no
  # tests**.  The whole tests/ directory — the suite and its seven UPF fixtures
  # from GBRV, SG15, PseudoDojo, ATOMPAW and pslibrary — arrived in 1.0.0, and
  # the sdist for 0.9.5 does not carry it either.  Packaging 0.9.5 therefore
  # meant a pytestCheckPhase that collected zero items and reported success.
  #
  # The bump is safe at the API: the public surface is `from .upf_to_json
  # import upf_to_json` at both tags, and aiida-core's only call site
  # (src/aiida/orm/nodes/data/upf.py) passes exactly the
  # `upf_to_json(text, fname=...)` signature the 1.0.0 suite exercises.  The
  # diff between the two is a rewrite of the two parsers, not an API change.
  #
  # It is *not* byte-identical in output, which an earlier version of this note
  # claimed too broadly.  1.0.0 emits an extra `label` ('5S', '5P', ...) on
  # each chi entry, and aiida-core carries a reference Ba.json generated with
  # 0.9.x, so its `test_upf2_to_json_barium` sees a key the reference lacks.
  # That one test is deselected in ../aiida-core, where the reason is spelled
  # out; nothing in aiida's own code reads the field.
  #
  # It does need ../aiida-core to relax `upf_to_json~=0.9.2`; see the
  # pythonRelaxDeps list there.
  src = fetchFromGitHub {
    owner = "simonpintarelli";
    repo = "upf_to_json";
    tag = version;
    hash = "sha256-fRx/Bv+9lQEumD1Q1d6hom7CXQU65p8UREIocm6lO00=";
  };

  build-system = [ setuptools ];

  # numpy and scipy were dependencies of the 0.9.x series and are not imported
  # anywhere in 1.0.0 — the parsers now use only json, re and ElementTree.
  dependencies = [ click ];

  nativeCheckInputs = [
    pytestCheckHook
    deepdiff
  ];

  # tests/test_upf_to_json.py opens its fixtures by bare relative filename
  # (`open("cr_pbe_v1.5.uspp.F.UPF")`), so it only passes with tests/ as the
  # working directory.  From the source root every case fails on FileNotFound.
  preCheck = ''
    cd tests
  '';

  pythonImportsCheck = [ "upf_to_json" ];

  meta = {
    description = "Convert pseudopotential files in UPF format to JSON";
    homepage = "https://github.com/simonpintarelli/upf_to_json";
    license = lib.licenses.bsd2;
    mainProgram = "upf2json";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
