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
  procps,
}:

buildPythonPackage {
  pname = "aiida-diff";
  version = "2.0.0-unstable-2024-01-29";
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

  # See ../aiida-cp2k for why this is a rewrite rather than a version bump, and
  # why pgtest, postgresql and the locale export left with it.
  #
  # The module path is only half of it, and the half that fails loudly.  The new
  # plugin also **dropped thirteen fixtures**, so a conftest that loads cleanly
  # can still collect nothing:
  #
  #   E       fixture 'clear_database' not found
  #   E       fixture 'aiida_local_code_factory' not found
  #
  # `clear_database` and its four siblings are replaced by `aiida_profile_clean`,
  # which resets the storage rather than the whole profile.  And
  # `aiida_local_code_factory` is not renamed to `aiida_code_installed` so much
  # as replaced by it: the old one took `(entry_point, executable)` and searched
  # PATH for the executable, the new one takes keywords and stores what it is
  # given.  A bare name is still fine — `validate_filepath_executable` skips any
  # path that is not absolute, and the program is on PATH here through
  # nativeCheckInputs — so only the argument names move.
  postPatch = ''
    substituteInPlace conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def clear_database_auto(clear_database):' \
        'def clear_database_auto(aiida_profile_clean):' \
      --replace-fail \
        'def diff_code(aiida_local_code_factory):' \
        'def diff_code(aiida_code_installed):' \
      --replace-fail \
        'aiida_local_code_factory(executable="diff", entry_point="diff")' \
        'aiida_code_installed(filepath_executable="diff", default_calc_job_plugin="diff")'
  '';

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

  nativeCheckInputs = [
    pytestCheckHook

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
