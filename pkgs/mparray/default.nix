{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  uv-build,

  # dependencies
  mpmath,
  numpy,
  scipy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "mparray";
  version = "0.2.2";
  pyproject = true;

  # Arbitrary-precision arrays behind the array API, on mpmath.  Here as one of
  # the backends ../array-api-extra's suite runs against.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/mparray.
  src = fetchFromGitHub {
    owner = "mdhaber";
    repo = "mparray";
    tag = "v${version}";
    hash = "sha256-5WoL4eZcqzEZ3Qvar/gDyZy/VlT8bLXaKLG1T0Aq5Dg=";
  };

  # `uv_build>=0.10.8,<0.11.0` against nixpkgs' 0.11.28.  The upper bound is
  # uv's own advice for any build backend it ships, not a known break, and
  # pythonRelaxDeps cannot reach a `[build-system]` requirement; see
  # ../aiida-core/default.nix.  The project has no build configuration beyond
  # the defaults: src/ layout, and a static version.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"uv_build>=0.10.8,<0.11.0"' '"uv_build>=0.10.8"'
  '';

  build-system = [ uv-build ];

  dependencies = [
    mpmath
    numpy
    scipy
  ];

  # Upstream's `tests` task is `pytest tests/ -v`; its pixi feature adds only
  # reporting and coverage plugins.  tools/xp-tests-*.txt belong to the
  # separate array-api-tests conformance run, which is not packaged.
  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [
    "mparray"
    "mparray.special"
    "mparray.testing"
  ];

  meta = {
    description = "Array API-compatible, arbitrary-precision arrays";
    homepage = "https://github.com/mdhaber/mparray";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
