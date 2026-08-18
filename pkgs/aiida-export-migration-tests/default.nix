{
  lib,
  python,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
}:

buildPythonPackage rec {
  pname = "aiida-export-migration-tests";
  version = "0.9.0";
  pyproject = true;

  # Data, not code: a set of AiiDA export archives in every historical format,
  # which ../aiida-core's tests/tools/archive/migration reads back to check that
  # each still migrates to the current schema.  aiida-core pins it at exactly
  # ==0.9.0, and v0.9.0 is the newest tag, so there is no range to track.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-export-migration-tests";
    tag = "v${version}";
    hash = "sha256-8EILkkutOcZkbqmfLIEZV2uZCOWY74lKCW98aI9cCs0=";
  };

  build-system = [ setuptools ];

  # The importable name is `aiida-export-migration-tests`, hyphens and all —
  # the directory holding __init__.py is spelled that way on disk.  That is not
  # a Python identifier, so it can never be reached by an `import` statement,
  # and pythonImportsCheck (which builds one) would fail on syntax rather than
  # on anything real.  aiida-core does not use `import` either: its
  # tests/tools/archive/migration/conftest.py passes
  # `external_module='aiida-export-migration-tests'` and resolves it through
  # importlib, which takes an arbitrary string.
  #
  # So the check below asks the only question that matters — did the archives
  # land where importlib will find them — rather than pretending the module is
  # importable.
  pythonImportsCheck = [ ];

  # setup.py declares `packages=find_packages()`, and that a hyphenated
  # directory survives it is luck rather than design: find_packages only asks
  # whether a directory holds __init__.py.  setuptools 83 still returns
  # ['aiida-export-migration-tests'], but a future version that filtered on
  # str.isidentifier() would quietly produce a wheel with no archives in it and
  # nothing else here would notice — the package has no tests and no importable
  # module to check.  Hence an explicit assertion rather than trust.
  postInstall = ''
    archives="$out/${python.sitePackages}/aiida-export-migration-tests/archives"
    if [ ! -d "$archives" ]; then
      echo "aiida-export-migration-tests: archives/ did not reach $archives" >&2
      echo "setup.py uses find_packages(); check it still returns the" >&2
      echo "hyphenated directory, which is not a Python identifier." >&2
      exit 1
    fi
  '';

  meta = {
    description = "Export archives for AiiDA's archive migration tests";
    homepage = "https://github.com/aiidateam/aiida-export-migration-tests";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
