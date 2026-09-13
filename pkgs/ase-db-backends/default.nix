{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,

  # dependencies
  ase,
  cryptography,
  lmdb,
  numpy,
  psycopg2,
  pymysql,

  # tests
  pytestCheckHook,
}:

# ase-db-backends — the ASE database backends that were split out of ase
# itself: PostgreSQL, MySQL/MariaDB, and the LMDB one.  Here for
# ../fairchem-core, which stores its datasets as `aselmdb`.  Internal, not
# re-exported.
#
# GitLab rather than GitHub, like ../hiphive and ../trainstation — ASE's whole
# organisation lives there.  Distribution and import are both
# `ase_db_backends`; the attribute is spelled with dashes.
buildPythonPackage {
  pname = "ase-db-backends";
  version = "0.11.0-unstable-2025-11-12";
  pyproject = true;
  __structuredAttrs = true;

  # HEAD.  The repository carries no tags at all, so there is nothing to say
  # whether this commit is the 0.11.0 release or past it — `pyproject.toml`
  # declares 0.11.0 statically and that is the whole of the evidence.  The
  # `-unstable-` suffix is the honest reading.
  src = fetchFromGitLab {
    owner = "ase";
    repo = "ase-db-backends";
    rev = "a9dc4c8ed35ca4167614f9a4ce5d96a285137c27";
    hash = "sha256-vSqGqmL9FwJLmzqqiOJcsIVFV55Xpx5RN2ac8iyq06I=";
  };

  # `version` is a plain string in pyproject.toml — no setuptools-scm here,
  # which is why this one needs no pretend version.
  build-system = [ setuptools ];

  # A real bug, not a test artefact: `close()` reached the environment through
  # the `env` property, which reopens when `_env` is None or the pid has
  # changed — so closing an already-closed database opened it, and closing one
  # in a forked child opened a second handle to the parent's file.  `__del__`
  # calls `close()`, so this ran at garbage collection.  py-lmdb refuses a
  # second `open()` of a path it already has registered, which turns the
  # mistake into an exception raised from inside `__del__` and leaves the path
  # registered for good.  The patch header has the whole account.
  #
  # It takes out any program that opens an `aselmdb` database twice in one
  # process, which ../fairchem-core does — a dataset and its splits are separate
  # handles.  Applying it removes the `__del__` failures from the build log
  # entirely; it is not, on its own, enough to make upstream's LMDB tests pass,
  # for which see `disabledTestPaths` below.
  patches = [ ./close-must-not-reopen.patch ];

  # Upstream asks for `psycopg2-binary`, which is the same source as psycopg2
  # published as a self-contained wheel with its own vendored libpq.  That
  # distinction is meaningless once nix is linking against a real libpq, and
  # nixpkgs' `psycopg2` is the package that provides the `psycopg2` module
  # either way.
  pythonRemoveDeps = [ "psycopg2-binary" ];

  dependencies = [
    ase
    cryptography
    lmdb
    numpy
    psycopg2
    pymysql
  ];

  # `ase` twice — once above as a runtime dependency, and again here for its
  # *console script*.  `test_db` populates the database by shelling out to a
  # nine-stage `ase -T build ... | ase -T run emt ...` pipeline, and a
  # propagated Python dependency puts its module on PYTHONPATH without putting
  # its `bin/` on PATH.  The test runs that pipeline through
  # `subprocess.run(..., shell=True)` and never checks the return code, so
  # without this the whole thing fails silently, the database stays empty, and
  # the failure surfaces much later as `KeyError: 'no match'`.
  # ../aiida-gaussian-datatypes lists a dependency twice for the same reason.
  nativeCheckInputs = [
    pytestCheckHook
    ase
  ];

  # The tests live *inside* the installed package rather than in a top-level
  # `tests/`, and upstream's `pytest.ini` points `testpaths` at them.  Naming
  # the path keeps this honest about which copy is being collected.
  #
  # Two of the five modules want a live server — `test_mysql.py` and
  # `test_sql_db_ext_tables.py`, the latter parameterised over postgresql,
  # mysql and mariadb — and both call `pytest.skip` when they cannot connect,
  # so they report as skips rather than failures here — ../../tests/materials/vm.nix
  # runs them against real servers.  That leaves the three LMDB modules as the
  # whole of what this build verifies, which is why both the `close()` patch
  # above and the py-lmdb pin in ../../overlays matter: without either, all
  # three fail and this suite verifies nothing at all.
  enabledTestPaths = [ "ase_db_backends/tests" ];

  # Nothing is deselected.  Two modules were, until the overlay pinned py-lmdb
  # to 1.7.3: both open one path twice in a process — `test_db2` nested inside
  # its own context manager, `test_aselmdb_concurrency` across eight forked
  # workers — which py-lmdb 2.x refuses outright and 1.x allows.  See the `lmdb`
  # binding in ../../overlays for why that pin exists.

  pythonImportsCheck = [
    "ase_db_backends"
    "ase_db_backends.aselmdb"
    "ase_db_backends.mysql"
    "ase_db_backends.postgresql"
  ];

  meta = {
    description = "PostgreSQL, MySQL and LMDB backends for the ASE database";
    homepage = "https://gitlab.com/ase/ase-db-backends";
    # "either version 2.1 of the License, or (at your option) any later
    # version" — the LGPL-2.1 grant, not the 3.0 one the sibling COPYING file
    # might suggest.
    license = lib.licenses.lgpl21Plus;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
