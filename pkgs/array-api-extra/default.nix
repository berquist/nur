{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  meson-python,

  # dependencies
  array-api-compat,

  # tests
  pytestCheckHook,
  pytest-xdist,
  array-api-strict,
  dask,
  hypothesis,
  jax,
  jaxlib,
  mparray,
  numpy,
  scipy,
  scipy-doctest,
  sparse,
  torch,
}:

let
  # The sparse backend's tests need 0.19.2, the floor upstream's pixi `backends`
  # feature names, and nixpkgs has 0.18.0.  Four tests fail on 0.18, both times
  # on sparse bugs that 0.19 fixed:
  #
  #   - TestNanMean::test_{simple,scalar,device[sparse-None]}: nanmean calls
  #     `xp.ones_like(count)`, and on 0.18 a full reduction returns a numpy
  #     scalar, which `ones_like` rejects with "The given format is not
  #     supported: float64".  pydata/sparse 42d6ad3 (#932) returns a 0-D array
  #     instead.
  #   - TestNUnique::test_nan: 0.18 counts the two NaNs in [nan, 123, nan] as
  #     one value.  pydata/sparse b3822d1 (#945) treats them as distinct.
  #
  # Overridden here, for this check phase alone, rather than in an overlay:
  # nothing else in this repository asks for a newer sparse, and replacing
  # nixpkgs' for every consumer would be a larger promise than four tests.  The
  # guard hands back nixpkgs' own derivation once it catches up.  This version
  # is not an attribute, so the updater never sees it; it moves by hand.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/sparse.
  # `sparse/_version.py` is export-subst, which does not affect a hash taken at
  # a tag.
  sparseForTests =
    if lib.versionAtLeast sparse.version "0.19.2" then
      sparse
    else
      sparse.overridePythonAttrs {
        version = "0.19.2";
        src = fetchFromGitHub {
          owner = "pydata";
          repo = "sparse";
          tag = "0.19.2";
          hash = "sha256-9RXiM5t0U64kKjMnz8Ram0qQm8QKNrOnO3OnFR/shdg=";
        };
      };
in
buildPythonPackage rec {
  pname = "array-api-extra";
  version = "0.11.4";
  pyproject = true;

  # Carried for ../colour-science's `array-api` extra, which nixpkgs cannot
  # supply: it has array-api-compat but not this.
  #
  # fetchFromGitHub because the suite lives in tests/, beside src/, and the
  # doctests below need docs/conftest.py.  Hash from
  # ../../scripts/offline-src-hash.sh against a clone in wc/array-api-extra.
  src = fetchFromGitHub {
    owner = "data-apis";
    repo = "array-api-extra";
    tag = "v${version}";
    hash = "sha256-ekwYHKEpJfUePbZXV5hY/f8FuX9Jwa8Ee6Q4SStJugw=";
  };

  build-system = [ meson-python ];

  # tests/meson.build installs the whole suite into array_api_extra/tests under
  # meson's `tests` install tag, and meson-python installs every tag unless
  # told otherwise.  `py.install_sources` tags the library `python-runtime`,
  # so this keeps the wheel to the library.
  pypaBuildFlags = [ "-Cinstall-args=--tags=runtime,python-runtime" ];

  dependencies = [ array-api-compat ];

  # Upstream's `tests` pixi feature, plus its `backends` feature.  The conftest
  # parametrizes every test over every backend in `Backend` and reaches each
  # through `pytest.importorskip`, so a backend left out is a set of skips
  # rather than failures.  Each one given here runs the whole of tests/main
  # again against a different array library, which is the point of the suite.
  #
  # What stays out: cupy and the `:gpu` variants, which need a CUDA device and
  # skip without one, and pytest-run-parallel, which is the free-threading
  # environment's.  array-api-strict is 2.5 against pixi's `>=2.6.1`; it is not
  # a declared dependency, and the suite passes on it.  sparse is the
  # `sparseForTests` above.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    array-api-strict
    dask
    hypothesis
    jax
    jaxlib
    mparray
    numpy
    scipy
    scipy-doctest
    sparseForTests
    torch
  ];

  # Upstream's `tests` task is `pytest -v tests/main`.  tests/vendoring imports
  # a copy of array_api_compat that a pixi task places there first, and
  # tests/run_deps is written for an environment without numpy; both have their
  # own pixi environments upstream and neither belongs in this one.
  enabledTestPaths = [ "tests/main" ];

  # Upstream's `doctests` task, verbatim: from docs/, so that docs/conftest.py
  # configures scipy-doctest, against the installed package.
  postCheck = ''
    pushd docs
    pytest -c ../pyproject.toml --pyargs array_api_extra \
      --doctest-modules --doctest-collect=api --doctest-only-doctests=true
    popd
  '';

  pythonImportsCheck = [
    "array_api_extra"
    "array_api_extra.testing"
  ];

  meta = {
    description = "Extra array functions built on top of the array API standard";
    homepage = "https://github.com/data-apis/array-api-extra";
    changelog = "https://github.com/data-apis/array-api-extra/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
