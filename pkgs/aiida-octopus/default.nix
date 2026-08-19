{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  postopus,

  # tests
  pytestCheckHook,
  numpy,
  octopus,
  procps,
  which,
}:

buildPythonPackage {
  pname = "aiida-octopus";
  version = "0.1.0-unstable-2026-08-16";
  pyproject = true;

  # GitLab, not GitHub, and the only one in this family that is.  There are no
  # tags and no PyPI release at all; the version below is the static
  # `0.1.0` in pyproject.toml with the checkout's date appended.
  src = fetchFromGitLab {
    owner = "octopus-code";
    repo = "aiida-octopus";
    rev = "4903d6b94de74c3a2b57987c493fbf16433a7345";
    hash = "sha256-7/PqAL55a1rwWtnUpbK42MTqfLx4X4Re4kh59HC5ViY=";
  };

  build-system = [ flit-core ];

  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [
    aiida-core
    postopus
  ];

  nativeCheckInputs = [
    pytestCheckHook
    numpy

    # tests/conftest.py prefers `aiida.tools.pytest_fixtures`, the modern
    # module, which uses core.sqlite_dos with no broker and needs no services —
    # so unlike the other plugins here this one wants neither pgtest nor
    # postgresql.  What it does want is the binary: the `octopus_executable`
    # fixture runs `which octopus` and raises if it is absent.
    octopus

    which

    # The `direct` scheduler polls the job it started with
    # `ps -o pid,stat,user,time`, and a Nix build sandbox has no procps.  The
    # test does not fail there — schedulers/plugins/direct.py only logs the
    # empty joblist as a warning — so the run continues, the calculation is
    # reported finished before it has written anything, and the assertion that
    # lands is a KeyError on a parsed output the parser never got:
    #
    #     WARNING aiida.scheduler.direct: Warning in _parse_joblist_output,
    #       non-empty (filtered) stderr='bash: line 1: ps: command not found'
    #     FAILED tests/test_ground_state.py::test_gs_molecule
    #       - KeyError: 'convergence'
    #
    # ../aiida-core carries procps for the same reason and says so at greater
    # length; this is the plugin half of it.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # test_gs_molecule is a real Octopus run — a benzene ground state cut to three
  # SCF iterations — driven through `engine.run`, which executes in-process and
  # so needs no daemon.  It asserts the converged energy and the force
  # components to nine significant figures against numbers recorded from one
  # particular Octopus build.  If this package fails its checkPhase on a
  # numerical mismatch rather than an error, that is upstream's tolerance being
  # tighter than the version skew between nixpkgs' octopus and theirs, and the
  # fix belongs in a `disabledTests` entry with the observed numbers quoted —
  # not in disabling the suite.
  pythonImportsCheck = [
    "aiida_octopus"
    "aiida_octopus.calculations.ground_state"
    "aiida_octopus.parsers.ground_state"
  ];

  meta = {
    description = "AiiDA plugin for running and parsing Octopus calculations";
    homepage = "https://gitlab.com/octopus-code/aiida-octopus";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
