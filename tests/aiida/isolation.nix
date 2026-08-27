# Module-isolation check for aiida-core's test suite.
#
#   nix-build tests/aiida/isolation.nix --no-out-link
#   nix-build tests/aiida/isolation.nix --argstr only tests/tools/workflows
#
# The mirror image of ./ordering.nix.  That file asks whether a test breaks when
# a *polluter* runs before it; this one asks whether a test breaks when nothing
# runs before it at all.
#
# Both are the same disease seen from opposite ends.  Under 128 xdist workers a
# worker holds a sparse subsequence of the collection, so a test may be preceded
# by almost nothing — and a test that quietly depends on a neighbour having
# already run then fails, at a rate set by the same lottery.  The known instance
# is tests/tools/workflows/test_base.py's
# test_fallback_workflow_tools_on_loading_error, which replaces
# aiida.plugins.entry_point.load_entry_point with one that always raises and only
# then builds a WorkChainNode.  Constructing a node needs the storage backend,
# which resolves through the function just replaced:
#
#     StorageFactory('core.psql_dos') -> BaseFactory -> load_entry_point
#     LoadingEntryPointError: broken tools entry point
#
# get_profile_storage caches after first use, so it passes whenever anything on
# that worker has already touched the database — which is nearly everything, and
# is why upstream never sees it.  Running each module alone makes that class
# deterministic rather than a draw.
#
# One derivation, not one per module.  Two hundred derivations would each
# rebuild and reinstall aiida-core to run one file; this builds it once and loops
# in the check phase, which is the same coverage for a fraction of the machine
# time.  Every module is run even after one fails, and the failures are listed
# together at the end — a harness that stops at the first is nearly useless here,
# since the whole question is *how many* modules have this problem.
#
# Each module still runs under xdist, with a small worker count.  Turning xdist
# off entirely is what hangs tests/engine/test_launch.py until pytest-timeout's
# 240s fires — see the note above postPatch in ../../pkgs/aiida-core/default.nix.
# A separate pytest session per module is what provides the isolation; the worker
# count inside a session is irrelevant to it.
#
# Expect false positives on the first run and triage them, rather than treating
# the list as a defect count. A module can fail alone for reasons that are not
# pollution — a fixture that legitimately lives in a sibling module's conftest,
# or a test whose data is built by a session-scoped fixture that upstream only
# ever exercises as part of the whole suite.

{
  pkgs ? import <nixpkgs> {
    overlays = [ (import ../../overlays).aiida ];
  },

  # Restrict to modules whose path starts with this, to iterate on one directory
  # without paying for the whole suite.
  only ? "tests",

  # Workers per module.  Small on purpose: the cost here is dominated by the
  # PostgreSQL cluster each session starts, not by the tests.
  workers ? 4,
}:

let
  inherit (pkgs) lib;

  aiida-core = pkgs.python313Packages.aiida-core;
in
aiida-core.overridePythonAttrs (old: {
  pname = "aiida-core-isolation";

  # The stock hook runs the whole suite once.  This needs one session per module,
  # so the phase is written out here instead — which also means the flag list has
  # to be rebuilt by hand, including the `-k` that pytestCheckHook would
  # otherwise assemble from `disabledTests`.
  dontUsePytestCheck = true;

  installCheckPhase = ''
    runHook preCheck

    # Same exclusions as the real suite. Losing them would drown the report in
    # tests that never run in CI either -- the five that reach the network, and
    # the SSH set that lives in ../../tests/aiida/vm.nix.
    flags=(
      ${lib.escapeShellArgs (builtins.filter (f: f != "--numprocesses=128") old.pytestFlags)}
      -k ${lib.escapeShellArg (lib.concatMapStringsSep " and " (t: "not (${t})") old.disabledTests)}
      --numprocesses=${toString workers}
    )

    # The other half of "same exclusions as the real suite", and the half that
    # pytest will not do for us.  Handing it `--ignore-glob` per
    # disabledTestPaths entry -- the obvious spelling, and what this used to do
    # -- is silently inert here: pytest consults pytest_ignore_collect only for
    # paths it *discovers*, and Session._collectfile guards that hook with
    # `if not self.isinitpath(fspath)`.  Every module below is named on the
    # command line, so it is an initial path and the hook never fires.  The
    # symptom was the three relocated SSH modules reported as isolation
    # failures, at 162 failures apiece, for want of an sshd rather than for want
    # of a predecessor test.  So filter the list instead of asking pytest to.
    excluded=(${lib.escapeShellArgs old.disabledTestPaths})

    mapfile -t found < <(find ${lib.escapeShellArg only} -name 'test_*.py' | sort)

    modules=()
    dropped=0
    for module in "''${found[@]}"; do
      keep=1
      for glob in "''${excluded[@]}"; do
        # Unquoted right-hand side deliberately: these entries are globs, and
        # bash's own pattern match is what stands in for pytest's fnmatch.
        # shellcheck disable=SC2053
        if [[ $module == $glob ]]; then
          keep=0
          dropped=$((dropped + 1))
          break
        fi
      done
      if [ "$keep" -eq 1 ]; then
        modules+=("$module")
      fi
    done

    echo "isolation: ${"\${#modules[@]}"} module(s) under ${only}, ${toString workers} workers each ($dropped excluded)"

    failed=()
    for module in "''${modules[@]}"; do
      echo "::: $module"
      if python -m pytest "''${flags[@]}" "$module"; then
        :
      else
        # 5 is "no tests collected", which is not a failure for a module whose
        # every test the exclusions above remove.
        status=$?
        if [ "$status" -eq 5 ]; then
          echo "::: $module — nothing collected, skipped"
        else
          failed+=("$module")
          echo "::: $module — FAILED ($status)"
        fi
      fi
    done

    echo
    echo "============================================================"
    if [ ''${#failed[@]} -eq 0 ]; then
      echo "isolation: all ''${#modules[@]} module(s) pass alone"
      echo "============================================================"
    else
      echo "isolation: ''${#failed[@]} of ''${#modules[@]} module(s) fail in isolation"
      echo "============================================================"
      printf '  %s\n' "''${failed[@]}"
      exit 1
    fi

    runHook postCheck
  '';

  meta = old.meta // {
    description = "aiida-core's test modules, each run in a session of its own";
  };
})
