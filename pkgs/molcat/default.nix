{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  numpy,
  pydantic,

  # From a flake input; see ../metallogen/default.nix and
  # ../harmonwig/default.nix for why this is defaulted.
  cclib ? null,

  # tests
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "molcat";
  version = "0.1.0-unstable-2026-03-04";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "sachin-sankar";
    repo = "molcat";
    rev = "60bbf698ba07da29cc1f0f15f7726ceb6a669780";
    hash = "sha256-eQjPKON5ykAFEVc2DUwrIMthgXEnN0bAETZkOg+CkR0=";
  };

  build-system = [ hatchling ];

  dependencies = [
    cclib
    numpy
    pydantic
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # **This package installs a top-level module named `src`.**
  #
  # pyproject.toml says `[tool.hatch.build.targets.wheel] packages = ["src"]`,
  # and the modules sit directly in that directory rather than in a `src/molcat`
  # beneath it.  So the distribution is called `molcat` while the import name is
  # `src`, and its own suite says `from src.lib import ...`.
  #
  # That is an upstream packaging mistake, not a Nix one, and it is left alone
  # here rather than patched: rewriting the layout would mean moving four
  # modules and rewriting every import in the package and its tests, which is a
  # fork rather than a package.  It is called out because the consequence is
  # shared: any environment containing molcat has a top-level `src` in it, and
  # a second package making the same mistake would collide with it.
  #
  # Anything building an environment with molcat in it should know that before
  # being surprised by it.
  pythonImportsCheck = [
    "src"
    "src.lib"
    "src.models"
  ];

  meta = {
    description = "Gaussian output log file extraction and aggregation";
    homepage = "https://github.com/sachin-sankar/molcat";
    # **No license at all.**  The repository has no LICENSE file, pyproject.toml
    # declares no `license` field or classifier, and the README says nothing —
    # so the default applies and all rights are reserved.  `unfree` is the
    # accurate spelling of that, and it is also load-bearing: ci.nix filters on
    # `meta.license.free`, so this keeps the package out of the cache-population
    # build set rather than redistributing something nobody granted a licence
    # for.  Change it if upstream ever adds one.
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ berquist ];
    broken = cclib == null;
  };
}
