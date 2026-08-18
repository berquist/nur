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
  pname = "profilehooks";
  version = "1.13.0";
  pyproject = true;

  # Carried here only because ../disk-objectstore installs
  # disk_objectstore/examples/example_objectstore.py, which imports this at
  # module scope.  Upstream lists it in the `examples` extra, so the module ships
  # in the wheel while the dependency that makes it importable does not.
  #
  # 1.13.0 rather than the tip: it is the release that added Python 3.13, and the
  # unreleased 1.14 series drops the older interpreters for 3.14 support this
  # repo has no use for.  Upstream tags without a `v` prefix from 1.7.1 onwards.
  src = fetchFromGitHub {
    owner = "mgedmin";
    repo = "profilehooks";
    tag = version;
    hash = "sha256-Y0p1OL8zAApFm/mrwMVOBcLyLpsx/DN9HHXl/kzrfvU=";
  };

  build-system = [ setuptools ];

  # No dependencies at all — a single module over cProfile, trace and timeit.

  nativeCheckInputs = [ pytestCheckHook ];

  # No `pytestFlags = [ "--override-ini=addopts=" ]` here, unlike most of its
  # neighbours.  Upstream's pytest.ini carries `--doctest-modules` and
  # `doctest_optionflags = ELLIPSIS`, and it needs no plugin that is missing:
  # most of this suite is doctests hung off `doctest_*` functions, and the
  # ELLIPSIS flag is what lets their expected output elide timings.  Clearing
  # addopts would drop the flags and quietly shrink the run.
  #
  # 17 tests collected; checked against `python test_profilehooks.py`, which is
  # how tox.ini runs it, and which reports the same 17.

  pythonImportsCheck = [ "profilehooks" ];

  meta = {
    description = "Decorators for profiling/timing/tracing individual functions";
    homepage = "https://github.com/mgedmin/profilehooks";
    changelog = "https://github.com/mgedmin/profilehooks/blob/${version}/CHANGES.rst";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
