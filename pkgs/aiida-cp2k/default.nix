{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  aiida-gaussian-datatypes,
  aiida-pseudo,
  ase,
  cp2k-output-tools,
  ruamel-yaml,
  upf-to-json,

  # tests
  pytestCheckHook,
  cp2k,
  procps,
}:

buildPythonPackage rec {
  pname = "aiida-cp2k";
  version = "2.1.1";
  pyproject = true;

  # fetchFromGitHub rather than fetchPypi even though 2.1.1 is released, because
  # examples/ is what supplies this package's test data — the basis set and
  # pseudopotential files the DFT example reads — and aiida-cp2k's pyproject.toml
  # has no [tool.flit.sdist] section pinning what the sdist carries.  The tag is
  # the same commit either way.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-cp2k";
    tag = "v${version}";
    hash = "sha256-UjcZj5apv0nuLctNYoTzRK9SFo1xhVr0Mfehaf5P7FE=";
  };

  build-system = [ flit-core ];

  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    aiida-gaussian-datatypes
    aiida-pseudo
    ase
    cp2k-output-tools
    ruamel-yaml
    upf-to-json
  ];

  # Two things in conftest.py are written for upstream's Docker image and
  # cannot work anywhere else.
  #
  # The first is a session-scoped autouse fixture that shells out to
  # `aiida-pseudo install sssp`, which downloads from Materials Cloud.  Nothing
  # under test/ actually uses an SSSP family — the fixture is there for the
  # examples, which are not collected here — so the download is removed rather
  # than replaced by a packaged archive that would then go unused.  If the
  # examples are ever brought into checkPhase, this is where an offline
  # `aiida-pseudo install family <archive>` would go instead.
  #
  # The second is a code fixture hardcoding /opt/conda/envs/cp2k/bin/cp2k.psmp
  # and a `conda activate`.  Pointed at the real binary, it works.
  # `$(` and `\n` below are literal in a Nix indented string — only `${` would
  # need escaping — so these match the Python source exactly as written.
  # The plugin migration, and this is the copy of the reasoning the other twelve
  # point at.
  #
  # Upstream deleted `aiida.manage.tests.pytest_fixtures` in 01bd7146d, "Remove
  # leftover deprecated pytest fixtures" (#7631), on the grounds that "nothing
  # references the module anymore".  Nothing in aiida-core did.  Thirteen
  # packages here did, through their own conftests, and this is that migration.
  # It is a simplification rather than a rename.
  #
  # The deprecated plugin built its profile from `config_psql_dos({})`, so all
  # thirteen needed a real PostgreSQL: `pgtest` for a throwaway cluster,
  # `postgresql` for the binaries it starts, and a UTF-8 locale archive, because
  # aiida-core's Postgres helper creates the database with
  # `LC_COLLATE 'en_US.UTF-8'` and a cluster built from nixpkgs' glibc does not
  # have it — all 37 tests here used to error in setup with
  #
  #     psycopg.errors.WrongObjectType: invalid LC_COLLATE locale name:
  #     "en_US.UTF-8"
  #
  # It also hardcoded a `process_control` block naming RabbitMQ on
  # 127.0.0.1:5672, which ../aiida-core had to patch back to `backend: None`.
  #
  # `aiida.tools.pytest_fixtures` needs none of that.  Its `aiida_profile_factory`
  # defaults to `storage_backend = 'core.sqlite_dos'` and `broker_backend = None`,
  # and the `aiida_profile` docstring says so outright: "The profile defines no
  # broker and uses the ``core.sqlite_dos`` storage backend, meaning it requires
  # no services to run."  So pgtest, postgresql, glibcLocalesUtf8, stdenv and the
  # whole `preCheck` leave with the module path.  ../aiida-octopus arrived at
  # this shape first, from the other side — its conftest already named the
  # modern module, and its note is the one that had it right.
  #
  # Only the module path is rewritten, not the surrounding `pytest_plugins` line.
  # The thirteen conftests spell that line with single quotes, with double
  # quotes, with a trailing `# pylint: disable=invalid-name`, and in
  # ../aiida-psi4's case beside a second plugin; the path is the only part all of
  # them agree on, and `--replace-fail` still catches a conftest that stops
  # naming it.
  #
  # `--dist worksteal` below is safe on sqlite: `aiida_config` gives each session
  # its own `tmp_path_factory.mktemp(...)` directory, so two workers never share
  # a database file.  Where one would, ../aiida-core's
  # sqlite-dos-concurrent-access.patch supplies WAL and a 60-second busy timeout.
  postPatch = ''
    substituteInPlace conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def cp2k_code(aiida_local_code_factory):' \
        'def cp2k_code(aiida_code_installed):' \
      --replace-fail 'return aiida_local_code_factory(' 'return aiida_code_installed(' \
      --replace-fail 'entry_point="cp2k",' 'default_calc_job_plugin="cp2k",' \
      --replace-fail 'executable="/opt/conda/envs/cp2k/bin/cp2k.psmp"' \
                     'filepath_executable="${cp2k}/bin/cp2k.psmp"' \
      --replace-fail 'eval "$(command conda shell.bash hook 2> /dev/null)"\nconda activate cp2k\n' \
                     "" \
      --replace-fail 'subprocess.run(' 'list('

    # Eight tests take `clear_database` as a plain argument; see ../aiida-diff
    # for the fixture that replaced it.
    #
    # **It moves to the front of the signature, and that is the whole point.**
    # pytest instantiates fixtures in the order they are requested, and
    # `aiida_profile_clean` calls `reset_storage()`, which closes and rebuilds
    # the profile's storage.  Left where `clear_database` sat — last, after
    # `cp2k_basissets` and `cp2k_pseudos` — it wipes the storage those two have
    # just populated, and the node objects they handed back are pointing at a
    # backend that no longer exists:
    #
    #   aiida.common.exceptions.ClosedStorage: SqliteDosStorage[…]: closed
    #
    # All eight, every one of them at the first attribute read.  The deprecated
    # `clear_database` deleted rows without closing anything, which is why the
    # argument order never mattered before.  ../aiida-core's own note about
    # these rewrites says it in one line: `aiida_profile_clean` goes first so it
    # still runs before the other fixtures.
    substituteInPlace test/test_gaussian_datatypes.py \
      --replace-fail \
        '(cp2k_code, cp2k_basissets, cp2k_pseudos, clear_database):' \
        '(aiida_profile_clean, cp2k_code, cp2k_basissets, cp2k_pseudos):'
  '';

  nativeCheckInputs = [
    pytestCheckHook
    cp2k

    # The five tests in test/test_gaussian_datatypes.py are the only ones here
    # that run a real CP2K, and they need the `direct` scheduler to be able to
    # poll it: without `ps` the joblist comes back empty, the job is declared
    # finished about two seconds in, and the parser is handed a file CP2K was
    # still writing.  What that looks like is not a scheduler error but
    #
    #     [WARNING] Warning in _parse_joblist_output, non-empty (filtered)
    #       stderr='bash: line 1: ps: command not found'
    #     [WARNING] output parser returned exit code<303>: The output file was
    #       incomplete.
    #     assert 303 == 0
    #
    # ../aiida-octopus lost a whole ground state to the same missing program.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # `test`, singular, is the unit-test directory.  Restricting to it is a
  # scoping decision rather than a way of skipping something: upstream sets
  # `python_files = "test_*.py example_*.py"` with no `testpaths`, so a bare run
  # also collects examples/, and those submit real CP2K jobs through a running
  # AiiDA daemon.  A checkPhase has no daemon and no broker.  Those examples are
  # covered instead by the plugin-cp2k VM test in ../../tests/aiida/vm.nix,
  # where a daemon does exist.
  pytestFlags = [
    "test"
  ];

  pythonImportsCheck = [
    "aiida_cp2k"
    "aiida_cp2k.calculations"
    "aiida_cp2k.parsers"
    "aiida_cp2k.workchains"
  ];

  meta = {
    description = "AiiDA plugin for the CP2K electronic structure code";
    homepage = "https://github.com/aiidateam/aiida-cp2k";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
