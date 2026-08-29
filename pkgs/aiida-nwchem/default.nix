{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  numpy,

  # tests
  pytestCheckHook,
  pgtest,
  procps,
  mpiCheckPhaseHook,
  postgresql,
  ase,
  pymatgen,
  seekpath,
  spglib,
  nwchem,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-nwchem";
  version = "3.0.1";
  pyproject = true;

  # Not fetchPypi: `[tool.flit.sdist] exclude` drops `tests/`.  See
  # ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-nwchem";
    tag = "v${version}";
    hash = "sha256-uYAvgO77SsMay7hfS4ohhfSxTgj0Le57ioZ6AKTJT0I=";
  };

  build-system = [ flit-core ];

  # See ../aiida-orca/default.nix: our aiida-core is a pre-release, and
  # `aiida-core[atomic_tools]~=2.0` does not admit one.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    numpy
  ];

  # nixpkgs builds NWChem with `ARMCI_NETWORK="MPI-PR"` — the Global Arrays
  # communication layer running as an MPI *progress rank*, which dedicates one
  # rank per node to servicing remote memory access and does no computation.
  # Two ranks is therefore the minimum, and tests/conftest.py asks for one:
  #
  #   [0] Received an Error in Communication: (2) ranks per node, must be at
  #   least
  #   MPI_ABORT was invoked on rank 0 in communicator MPI COMM 3 DUP FROM 0
  #
  # aiida-nwchem's calcjob defaults `metadata.options.withmpi` to True, so this
  # is `mpirun -np 1 nwchem` and NWChem aborts before writing a single line —
  # which aiida reports as exit code 312, "The stdout output file was
  # incomplete", and the test as `assert 'output_parameters' in result` against
  # an empty log.  Nothing in the aiida layer says "MPI"; the message only
  # exists in the calculation's `_scheduler-stderr.txt`, which no assertion
  # prints.
  #
  # Two rather than one is the whole fix for the launch: one rank computes,
  # one drives progress, and `set_default_memory_per_machine(None)` on the next
  # line already keeps the sandbox from being asked for a memory limit it
  # cannot honour.
  #
  # NWChem then starts, and the other two rewrites are about what it is asked
  # to do.  All three tests hand the Gaussian DFT module a periodic geometry —
  # two through `builder.add_cell = orm.Bool(True)`, the third through a
  # `system crystal` block in tests/data/h2o.inp — and NWChem refuses:
  #
  #   dft_rdinput: detected periodicity =                    3
  #   current input line :  22: task dft
  #   There is an error in the input file
  #
  # That is not a build or a sandbox problem; it is upstream's tests being
  # older than the NWChem they now meet.  src/nwdft/input_dft/dft_rdinput.F
  # gained the check in 3561a7eff3 (2021-08-29, "another fix for bug
  # nwchemgit/nwchem#322"), first released in v7.2.0 — nixpkgs carries 7.3.1,
  # and aiida-nwchem 3.0.1's fixtures were evidently last run against a 7.0.x
  # that accepted the cell and ignored it.
  #
  # `system crystal` was never a Gaussian-DFT keyword.  doc/user/geometry.tex
  # documents it under "SYSTEM --- Lattice parameters for periodic systems",
  # says the coordinates must then be *fractional* — these are Cartesian
  # angstroms — and every use of it in NWChem's own tree is a plane-wave input:
  # QA/tests/pspw_SiC, QA/tests/talc, examples/pspw/.  Those run `task pspw` or
  # `task band`, not `task dft`.
  #
  # So the cell comes out, and the three tests run the molecular DFT they were
  # really exercising all along — the calcjob, the retrieval and the output
  # parser.
  #
  # **Dropping the block is not enough for tests/data/h2o.inp**, and this is the
  # trap in the whole exercise.  `system crystal` means the coordinates are
  # fractional — geometry.tex says so, and calculations/nwchem.py agrees, since
  # `add_cell` makes it multiply by the inverse cell before writing them.  That
  # fixture's numbers are fractions of a 4 Å cube, so deleting the block alone
  # reinterprets them as ångströms and silently shrinks the molecule to an O–H
  # of 0.45 Å.  It still converges — to -72.064734510054, measured — and would
  # have looked like a passing test.  Multiplying the two hydrogen rows by
  # `lat_a` keeps the geometry the periodic run had: O–H 1.8088 Å at 104.52°,
  # the stretched water upstream drew.
  #
  # The two builder tests need no such care: with `add_cell` false the plugin
  # writes the structure's own Cartesian positions, so their molecule is
  # unchanged.
  #
  # The last rewrite is a test that never tested anything.  Both energy checks
  # read
  #
  #   assert pytest.approx(parameters['total_dft_energy'], 0.1, -74.38)
  #
  # which is `approx(expected=<the value>, rel=0.1, abs=-74.38)` — the number
  # to compare against is passed as the *tolerance*, nothing is compared, and
  # the assertion is on the approx object itself.  Under pytest 9 that is no
  # longer even vacuously true:
  #
  #   AssertionError: approx() is not supported in a boolean context.
  #
  # Rewritten to the comparison the arguments plainly intend — and, since
  # upstream never ran it, measured rather than assumed.  Under this NWChem,
  # sto-3g, and the default functional:
  #
  #   the h2o.inp fixture, rescaled as above    -74.438279199677
  #   ase's equilibrium water (test_h2o)        -74.734937577192
  #
  # The first is 0.058 from upstream's -74.38, inside their own 0.1: that
  # number was recorded from this fixture, in the periodic run, and getting it
  # back is independent confirmation that reading the coordinates as fractional
  # and scaling by lat_a is the right reading.
  #
  # The second is 0.355 away, because it is a different molecule — equilibrium
  # water, not the stretched one — and the same assertion was copy-pasted into
  # both tests.  Vacuous assertions hide that sort of thing.  So test_h2o gets
  # the value it actually produces and test_h2o_base keeps upstream's.
  #
  # `float(...)`, because `output_parameters` holds strings.  parsers/nwchem.py
  # builds its dict straight out of the regex — `result_dict[key] =
  # result.group(2)` — and never casts, so the repaired comparison fails on the
  # type before it can fail on the number:
  #
  #   AssertionError: assert '-74.734937577168' == -74.73 ± 0.1
  #
  # That is also why upstream's version could never have worked even with the
  # arguments in the right order.  The cast belongs in the test rather than in
  # the parser: changing the parser would change this package's output for
  # every consumer, which is a different decision from fixing a test.
  #
  # Two rules, one anchored on a block: the two `assert pytest.approx` lines
  # are identical, and substituteInPlace replaces every occurrence.  Reaching
  # back to `add_cell` makes the first rule match test_h2o alone, after which
  # the bare line is unique to test_h2o_base.
  #
  # What this does give up is any coverage of `add_cell` actually reaching
  # NWChem.  It still generates its `system crystal` block, and nothing here
  # runs it, because nothing in this suite pairs it with a plane-wave task.
  postPatch = ''
      substituteInPlace tests/conftest.py \
        --replace-fail \
          'code.computer.set_default_mpiprocs_per_machine(1)' \
          'code.computer.set_default_mpiprocs_per_machine(2)'

      substituteInPlace tests/test_calculations.py \
        --replace-fail \
          'builder.add_cell = orm.Bool(True)' \
          'builder.add_cell = orm.Bool(False)' \
        --replace-fail \
          "    builder.add_cell = orm.Bool(False)

        result = engine.run(builder)

        with result['retrieved'].base.repository.open('aiida.out') as handle:
            log = handle.read()

        assert 'output_parameters' in result, log
        parameters = result['output_parameters'].get_dict()
        assert pytest.approx(parameters['total_dft_energy'], 0.1, -74.38)" \
          "    builder.add_cell = orm.Bool(False)

        result = engine.run(builder)

        with result['retrieved'].base.repository.open('aiida.out') as handle:
            log = handle.read()

        assert 'output_parameters' in result, log
        parameters = result['output_parameters'].get_dict()
        assert float(parameters['total_dft_energy']) == pytest.approx(-74.73, abs=0.1)" \
        --replace-fail \
          "assert pytest.approx(parameters['total_dft_energy'], 0.1, -74.38)" \
          "assert float(parameters['total_dft_energy']) == pytest.approx(-74.38, abs=0.1)"

      substituteInPlace tests/data/h2o.inp \
        --replace-fail '  system crystal
        lat_a 4.0
        lat_b 4.0
        lat_c 4.0
        alpha 90.0
        beta  90.0
        gamma 90.0
      end
      O 0.0 0.0 0.0
      H 0.0 0.3576070225 -0.276788165
      H 0.0 -0.3576070225 -0.276788165
    ' '  O 0.0 0.0 0.0
      H 0.0 1.43042809 -1.10715266
      H 0.0 -1.43042809 -1.10715266
    '
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, whose profile is a real PostgreSQL one.  See ../pgtest
    # for why postgresql is listed alongside it.
    pgtest
    postgresql

    # The `atomic_tools` extra of aiida-core.  `dependencies` above cannot carry
    # it — nixpkgs' buildPythonPackage has no notion of installing a dependency
    # *with* an extra — and the suite needs it: the `h2o` fixture calls
    # `ase.build.molecule`, and StructureData's symmetry handling reaches
    # spglib, seekpath and pymatgen.  Check inputs rather than dependencies
    # keeps them out of the runtime closure, which is where the extra is
    # optional by upstream's own reckoning.
    ase
    pymatgen
    seekpath
    spglib

    # NWChem in nixpkgs is an MPI build, and Open MPI needs more than one
    # concession before it will start inside a build sandbox: UCX enumerates
    # network devices through /sys/class/net, hwloc reads the cpu topology out
    # of sysfs, and the process launcher looks for an ssh agent — none of which
    # a sandbox has.  The first announces itself as
    #
    #   tcp_iface.c:991  UCX  ERROR scandir(/sys/class/net) failed:
    #   No such file or directory
    #
    # and the consequence, whichever of them bites, is that NWChem dies during
    # startup, aiida retrieves a truncated output file — exit code 312, "The
    # stdout output file was incomplete" — and the test reads that as a bare
    # `assert 'output_parameters' in result` against an empty log.
    #
    # This hook is nixpkgs' own answer, used by scalapack, scotch and sirius:
    # it detects the MPI implementation and sets `OMPI_MCA_pml=ob1` so UCX is
    # never initialised, `HWLOC_XMLFILE` to a preset topology, an
    # ssh-agent-free launcher, and oversubscription.  Setting `pml` and
    # `UCX_TLS` by hand here was tried first: it silenced the UCX error and the
    # run still produced nothing, because the topology file is the part that is
    # easy to miss.  The hook is also where nixpkgs keeps up with MCA names
    # changing between Open MPI 4 and 5.
    mpiCheckPhaseHook

    # The `direct` scheduler reads its joblist from `ps`, and without it aiida
    # cannot tell that the job has finished, so it retrieves the working
    # directory while NWChem is still writing:
    #
    #   Warning in _parse_joblist_output, non-empty (filtered) stderr=
    #     'bash: line 1: ps: command not found'
    #   output parser returned exit code<312>: The stdout output file was
    #     incomplete.
    #
    # which reaches the test as a bare `assert 'output_parameters' in result`
    # against an empty log.  ../aiida-cp2k/default.nix documents the same
    # failure wearing a different assertion.
    procps

    # All three tests really run NWChem — `engine.run` on an H2O/STO-3G DFT
    # single point — rather than asserting on a generated input file, and
    # `aiida_local_code_factory(executable='nwchem')` resolves the name through
    # PATH.  Both facts have to hold for the suite to run at all, which is why
    # this is a check input rather than a note about mocking.
    nwchem
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_nwchem"
    "aiida_nwchem.calculations"
    "aiida_nwchem.parsers"
    "aiida_nwchem.workflows"
  ];

  meta = {
    description = "AiiDA plugin for the NWChem quantum chemistry program";
    homepage = "https://github.com/aiidateam/aiida-nwchem";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
