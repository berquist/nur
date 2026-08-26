{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "wignernj";
  version = "0.8.0";
  pyproject = true;

  # The distribution is `wignernj`; the repository is `libwignernj`, which also
  # carries the C library, its Fortran bindings and a cmake build.  Only the
  # Python extension is built here — setup.py compiles the fifteen C sources
  # directly, so none of the cmake machinery is involved.
  src = fetchFromGitHub {
    owner = "susilehtola";
    repo = "libwignernj";
    tag = "v${version}";
    hash = "sha256-NJcLW+nFgQADOgvmYU8iNffiXYVgmTMeaUkDKbsgHAg=";
  };

  build-system = [ setuptools ];

  # No runtime dependencies at all: the extension is self-contained C, and the
  # `numpy` extra only adds array-valued convenience wrappers.

  nativeCheckInputs = [ pytestCheckHook ];

  # tests/python/test_wignernj_python.py opens with
  #
  #     try:  from wignernj import wigner3j, ...
  #     except ImportError:  pytest.skip(..., allow_module_level=True)
  #
  # and that skip is silent.  From the source root `import wignernj` resolves to
  # the `wignernj/` directory sitting right there, which is pure Python and has
  # no compiled `_wignernj` beside it — so the import fails, the module skips
  # itself, and the whole suite reports success having run nothing.  This is the
  # sdist-has-no-tests trap in a different disguise: the tests are present and
  # collected, they just all skip.
  #
  # Removing the source copy makes the import resolve to the installed
  # extension, which is the thing worth testing.  pythonImportsCheck below is
  # the second half of the guard — if the extension were somehow still
  # unimportable, that fails loudly rather than skipping.
  preCheck = ''
    rm -rf wignernj
  '';

  # testpaths in pyproject.toml already points at tests/python; the rest of
  # tests/ is the C and Fortran suite, driven by cmake.

  pythonImportsCheck = [ "wignernj" ];

  meta = {
    description = "Exact Wigner 3j/6j/9j, Clebsch-Gordan, Racah W, Fano X and Gaunt coefficients via prime factorization";
    homepage = "https://github.com/susilehtola/libwignernj";
    changelog = "https://github.com/susilehtola/libwignernj/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
