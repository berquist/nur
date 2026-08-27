{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  voluptuous,

  # tests
  pytestCheckHook,
  diffutils,
  pgtest,
  postgresql,
  procps,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage {
  pname = "aiida-diff";
  version = "1.2.0-unstable-2024-01-29";
  pyproject = true;

  # Here for ../aiida-testing, which is here for ../aiida-psi4.  This is the
  # AiiDA plugin-template example — a plugin whose "code" is `diff` — and the
  # third name in aiida-testing's `testing` extra, after pgtest and
  # pytest-datadir.  All six tests in its tests/mock_code/test_diff.py build a
  # code with `entry_point='diff'` and call `CalculationFactory('diff')`, so
  # they need these entry points registered and nothing else provides them.
  #
  # Two commits past v2.0.0 rather than the tag.  `updates for aiida 2.5` is one
  # of them, and it is what makes this work against an aiida-core 2.x at all:
  # it rewrites `transport_type="local"` and `scheduler_type="direct"` to their
  # `core.` spellings and drops a `codeinfo.withmpi` assignment.  Its own
  # `aiida.calculations` entry point stays `diff`, unprefixed, which is what
  # aiida-testing's CALC_ENTRY_POINT expects.
  #
  # The version is what upstream declares, per the convention in
  # ../aiida-octopus, and upstream declares it going backwards: that same commit
  # sets `__version__ = "1.2.0"` in a tree tagged v2.0.0.  Following the string
  # rather than the tag keeps the derivation name and the wheel metadata
  # agreeing, which is the point of the convention.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-diff";
    rev = "f9b151e11634b16e6a42d5445da23735415872e0";
    hash = "sha256-vD9oNJ9ppU6vWqGOH0o/msKfl62fjLF1r/H2aiQbp1o=";
  };

  build-system = [ flit-core ];

  # `aiida-core>=2.5,<3` against a 2.10.0.dev0 snapshot: a pre-release does not
  # satisfy that without an opt-in.  Every AiiDA plugin here needs this.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    voluptuous
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # conftest.py names `aiida.manage.tests.pytest_fixtures`, so the profile is
  # core.psql_dos and the cluster needs a locale it would not otherwise have —
  # ../pgsu/default.nix has the long version.
  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql

    # The plugin's whole subject.  Its `diff_code` fixture is
    # `aiida_local_code_factory(executable="diff", entry_point="diff")`, which
    # looks the program up on PATH, and test_process then runs it for real.
    diffutils

    # Which means the `direct` scheduler has to poll it — see ../aiida-cp2k for
    # what a missing `ps` costs a calculation that does complete.
    procps
  ];

  # `python_files = "test_*.py example_*.py"` with no `testpaths`, so a bare run
  # also collects examples/example_01.py.  That one builds its own computer and
  # code through aiida_diff.helpers and submits, which is a different thing from
  # what tests/ covers.  Same reasoning as ../aiida-cp2k's `test`.
  pytestFlags = [ "tests" ];

  pythonImportsCheck = [
    "aiida_diff"
    "aiida_diff.calculations"
    "aiida_diff.data"
    "aiida_diff.parsers"
  ];

  meta = {
    description = "AiiDA demo plugin wrapping the `diff` executable";
    homepage = "https://github.com/aiidateam/aiida-diff";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
