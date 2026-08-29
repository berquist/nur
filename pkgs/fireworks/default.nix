{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  flask,
  flask-paginate,
  gunicorn,
  jinja2,
  monty,
  numpy,
  pymongo,
  python-dateutil,
  ruamel-yaml,
  tabulate,
  tqdm,

  # tests
  graphviz,
  igraph,
  matplotlib,
  mongomock-persistence,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "fireworks";
  # 2.1.4, not the v2.0.2 that `git describe` reports for this commit: the tag
  # is behind, and setup.py here declares `version="2.1.4"`.  atomate2 and
  # jobflow both pin `FireWorks==2.1.4`, so the source is the one to believe.
  version = "2.1.4-unstable-2026-08-11";
  pyproject = true;

  # The distribution is `FireWorks`; the import name is `fireworks`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "fireworks";
    rev = "71686559d2a407c976cc56b6fa3c648819ee8fe3";
    hash = "sha256-J2fGV35MWsbgwoSyS2W7YBewFELFqZR6t5WyUS/kVn8=";
  };

  build-system = [ setuptools ];

  # monty 2026.7.16 made zopen's `mode` a required positional argument and
  # rejects an implicit text/binary mode outright.  2025.3.3 still defaults it
  # to "r", behind a FutureWarning whose own deadline was 2025-06-01.  FireWorks
  # never caught up, so its five bare calls in rocket.py — the offline-mode
  # reads at lines 150, 303, 365, 421 and 445 — are a TypeError on both unstable
  # legs of the matrix:
  #
  #   with zopen(fpath) as f_in:
  #   E  TypeError: zopen() missing 1 required positional argument: 'mode'
  #
  # Only one of the five is reached by the suite as it runs here —
  # LaunchPadOfflineTest::test__recover_completed, through rocket.py:150 — so
  # patching just that one would look like a fix and leave four TypeErrors in
  # the paths the mongomock partition never enters.  substituteInPlace replaces
  # every occurrence, and the indentation differs between the five while the
  # matched text does not, so one --replace-fail covers them all.
  #
  # "rt" rather than "r": it is what the old default resolved to for these
  # uncompressed .json reads, so this is equally right on nixos-26.05, where it
  # silences the implicit-mode warning rather than adding one.
  postPatch = ''
    substituteInPlace fireworks/core/rocket.py \
      --replace-fail \
        'with zopen(fpath) as f_in:' \
        'with zopen(fpath, "rt") as f_in:'
  '';

  dependencies = [
    flask
    flask-paginate
    gunicorn
    jinja2
    monty
    # Not declared by upstream, and needed anyway — `import fireworks` fails
    # without it:
    #
    #   File ".../fireworks/fw_config.py", line 11, in <module>
    #     from monty.serialization import dumpfn, loadfn
    #   File ".../monty/json.py", line 24, in <module>
    #     import numpy as np
    #   ModuleNotFoundError: No module named 'numpy'
    #
    # monty imports numpy unconditionally at the top of json.py, but nixpkgs
    # lists numpy only in monty's `optional-dependencies`, never in
    # `dependencies`.  So every monty dependant that reaches serialization has
    # to carry numpy itself.  That is a latent nixpkgs bug rather than ours;
    # repairing monty here instead would change it for every consumer of this
    # overlay, which is a bigger blast radius than the problem deserves.
    numpy
    pymongo
    python-dateutil
    ruamel-yaml
    tabulate
    tqdm
  ];

  nativeCheckInputs = [
    pytestCheckHook
    # setup.py's `workflow-checks` extra, needed because its tests ship inside
    # the package.  Without it collection aborts before a single test runs:
    #
    #   ERROR collecting fireworks/utilities/tests/test_dagflow.py
    #   fireworks/utilities/dagflow.py:9: in <module>
    #       import igraph
    #   E   ModuleNotFoundError: No module named 'igraph'
    #   !!!! Interrupted: 1 error during collection !!!!
    #
    # test_dagflow.py does guard for this — DAGFlowTest.setUp raises
    # unittest.SkipTest when igraph will not import — but the guard is dead
    # code: line 15 does `from fireworks.utilities.dagflow import DAGFlow` at
    # module scope, so the ImportError lands during collection and setUp is
    # never reached.  Supplying the dependency is the fix; deselecting the
    # module would lose the only coverage the DAG validator has.
    igraph

    #
    # DAGFlow.to_dot writes DOT through igraph's own write_dot(), so the three
    # to_dot tests do not need the separate `graph-plotting` extra.  The two
    # test_visualize.py tests do, and they fail loudly rather than skipping:
    #
    #   FAILED test_visualize.py::test_wf_to_graph
    #     - RuntimeError: graphviz package required for wf_to_graph.
    #   FAILED test_visualize.py::test_plot_wf
    #     - SystemExit: Install matplotlib. Exiting.
    #
    # Neither renders anything — wf_to_graph only asserts it gets a Digraph
    # back, and plot_wf never calls plt.show() — so the Python `graphviz`
    # binding is enough and the `dot` binary is not needed.
    graphviz
    matplotlib

    # setup.py's `mongomock` extra, which is what lets the database tests run
    # with no database.  See the MONGOMOCK_SERVERSTORE_FILE note below.
    mongomock-persistence
  ];

  # Three things the check phase needs, and only the first is obvious.
  #
  # HOME: matplotlib wants a writable config directory.  MPLBACKEND: makes the
  # backend choice explicit rather than leaving it to display autodetection —
  # nothing here calls plt.show(), so Agg is enough.
  #
  # MONGOMOCK_SERVERSTORE_FILE is the interesting one.  A real MongoDB is not
  # an option: every mongodb-ce in the locked nixpkgs is
  # `meta.license.free = false` under the SSPL, and ci.nix filters on
  # `meta.license.free`, so depending on one would silently drop fireworks out
  # of CI and the binary cache.
  #
  # Most of FireWorks' database coverage is not marked `mongodb` and simply
  # skips itself when no server answers, so a database-less build quietly ran
  # about a third less than it appeared to.  Nineteen more tests did not even
  # skip — they sat through pymongo's server-selection timeout and failed:
  #
  #   pymongo.errors.ServerSelectionTimeoutError:
  #     localhost:27017: [Errno 111] Connection refused
  #
  # which cost 17 minutes of wall clock to produce 20 failures, making it a
  # CI-time problem as much as a correctness one.
  #
  # fw_config.py's override_user_settings() reads this variable at import time
  # and, when it is set, swaps `MongoClient` for
  # `mongomock_persistence.MongoClient` and enables mongomock's gridfs
  # integration — which GRIDFS_FALLBACK_COLLECTION turns on by default.  That
  # took the run from 97 passed / 59 skipped / 20 failed in 17:06 to 157 passed
  # / 9 skipped / 12 failed in 2:24; see pytestFlags below for what is left.
  #
  # It has to be exported before fireworks is first imported, which is why it
  # lives here rather than in an `env` attribute alongside a pytest flag.
  #
  # The file is where the mock persists its JSON between clients, and it has to
  # exist before the first client is built: mongomock_persistence's
  # ServerStore.__init__ opens it for reading unconditionally once the variable
  # is set, so an absent path is a FileNotFoundError rather than an empty
  # database.  Seeding it with `{}` is what upstream's own test does.
  preCheck = ''
    export HOME="$(mktemp -d)"
    export MPLBACKEND=Agg
    export MONGOMOCK_SERVERSTORE_FILE="$(mktemp -d)/mongodb.json"
    echo '{}' > "$MONGOMOCK_SERVERSTORE_FILE"
  '';

  # What the mock cannot reach, deselected the way upstream says to.  Its own
  # marker description is the instruction: pyproject.toml declares
  #
  #   "mongodb: marks tests that need mongodb (deselect with '-m \"not mongodb\"')"
  #
  # and that marker turned out to be an exact partition of what was left: with
  # mongomock in place the run is 157 passed / 12 failed, and the twelve
  # failures are precisely the twelve `@pytest.mark.mongodb` tests — two on
  # GridfsStoredDataTest, two parametrisations of test_lpad_get_fws, and eight
  # in test_filepad_tasks.py.  Nothing marked passes; nothing unmarked fails.
  #
  # They fail three different ways, and each is a place mongomock diverges from
  # a real server rather than anything wrong here:
  #
  #   KeyError: 'gridfs_id'        GridfsStoredDataTest exists to check the
  #                                spill-to-GridFS path that only triggers when
  #                                a document exceeds MongoDB's 16MB limit.
  #                                mongomock enforces no such limit, so the
  #                                document is stored inline and never spills.
  #   assert '0\n' == '1\n'        the `[{$match: {}}, {$count: 'count'}]`
  #                                aggregation comes back empty under mongomock.
  #   assert None == b'...'        FilePad's GridFS content does not round-trip
  #                                through mongomock's gridfs integration.
  #
  # A marker rather than the paths and test names this used to list: upstream
  # maintains it, so a database test added later is excluded without anyone
  # here noticing it needs to be.  The mock is still very much earning its
  # place — it took the run from 97 passed / 59 skipped to 157 passed / 9
  # skipped, because most of FireWorks' database tests are not marked at all
  # and simply skipped themselves when no server answered.
  #
  # disabledTestMarks, not `pytestFlags = [ "-m" "not mongodb" ]`.  pytestFlags
  # reaches the hook through `concatTo`, which word-splits, so the marker
  # expression arrives as two arguments and pytest reads the second as a path:
  #
  #   pytest flags: -m pytest -m not mongodb
  #   collected 0 items
  #   ERROR: file or directory not found: mongodb
  #
  # The dedicated attribute builds `-m "not (mongodb)"` as one quoted argument.
  # Note it is silent about a mark that matches nothing, unlike disabledTestPaths
  # — so if this ever stops excluding anything, the run just gets longer.
  disabledTestMarks = [ "mongodb" ];

  # Several modules import `fw_tutorials.*`, which is a second top-level package
  # in this repository rather than a test fixture.  setup.py's bare
  # find_packages() picks it up (it carries four __init__.py files), so it is
  # installed alongside `fireworks` and the imports resolve.

  pythonImportsCheck = [
    "fireworks"
    "fireworks.core.firework"
    "fireworks.core.launchpad"
  ];

  meta = {
    description = "Workflow software for running high-throughput calculation workflows";
    homepage = "https://github.com/materialsproject/fireworks";
    changelog = "https://github.com/materialsproject/fireworks/blob/main/CHANGES.txt";
    license = lib.licenses.bsd3;
    # Four console scripts, none of them named after the package: lpad, mlaunch,
    # qlaunch and rlaunch.  lib.getExe would otherwise fall back to "fireworks"
    # and produce a path that does not exist.
    mainProgram = "lpad";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
