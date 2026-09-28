{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  glom,

  # optional-dependencies
  pint,

  # tests
  pytestCheckHook,
  numpy,
  pytest-regressions,
  pyyaml,
}:

buildPythonPackage rec {
  # The distribution name, not the attribute's: ../qe-tools' `dough==0.4.0` is
  # checked against this.
  pname = "dough";
  version = "0.4.0";
  pyproject = true;

  # Carried beside ../dough (0.6) for ../qe-tools alone, which pins
  # `dough==0.4.0`.  The pin is real: 0.5 removed `dough.outputs.output_mapping`,
  # and qe-tools 3.0.0a4 imports it in four modules.  Both install `dough`, so
  # the two cannot share an environment.  Delete this when qe-tools moves on.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/dough.
  src = fetchFromGitHub {
    owner = "mbercx";
    repo = "dough";
    tag = "v${version}";
    hash = "sha256-DE3T9S4xolYdP81LMT10t+AvDUCVVlIfyEpcKVW+Zes=";
  };

  build-system = [ hatchling ];

  dependencies = [ glom ];

  # `pint>0.24,<0.25` upstream, against nixpkgs' 0.25.3.  An extra is not
  # something pythonRuntimeDepsCheckHook reads, so this builds either way; the
  # check phase below is what says whether 0.25 works.  0.4.0 has no `inputs`
  # layer yet, and so no `pydantic` extra, unlike ../dough.
  optional-dependencies = {
    pint = [ pint ];
  };

  # The `tests` extra: pyyaml, pytest-regressions, numpy and `dough[pint]`.
  # tests/conftest.py loads `dough.testing.plugin`, which ships in the wheel.
  nativeCheckInputs = [
    pytestCheckHook
    numpy
    pytest-regressions
    pyyaml
  ]
  ++ optional-dependencies.pint;

  pythonImportsCheck = [
    "dough"
    "dough.converters"
    "dough.outputs"
    "dough.testing"
  ];

  # Read by ../../scripts/update-universe.nix.  The inferred `stable` would
  # offer the newest tag, which is exactly what this attribute exists not to
  # have.
  passthru.updatePolicy = {
    mode = "pinned";
    reason = "qe-tools pins dough==0.4.0, and 0.5 removed dough.outputs.output_mapping, which it imports";
  };

  meta = {
    description = "Framework for building typed Python wrappers around simulation code output files (0.4 series)";
    homepage = "https://github.com/mbercx/dough";
    changelog = "https://github.com/mbercx/dough/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
