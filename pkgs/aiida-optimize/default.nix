{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  decorator,
  numpy,
  pyyaml,
  scipy,

  # tests
  pytestCheckHook,
  pgtest,
  postgresql,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-optimize";
  version = "1.0.2";
  pyproject = true;

  # Not fetchPypi, for the usual reason — the sdist carries no `tests/` — and
  # here the suite is also where `sample_processes.py` lives, which every test
  # module imports.  See ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "greschd";
    repo = "aiida-optimize";
    tag = "v${version}";
    hash = "sha256-6ZxgnsYk7u+9njNAbXDQ5bqeu+jkG/gHc4O1gxcombs=";
  };

  build-system = [ setuptools ];

  # See ../aiida-orca/default.nix: our aiida-core is a pre-release, which
  # `aiida-core>=2.0.0,<3.0.0` does not admit.
  pythonRelaxDeps = [ "aiida-core" ];

  # setup.py carries no metadata of its own — it reads setup.json and splices
  # it into `setup()`, so `install_requires` is the list in that file.
  dependencies = [
    aiida-core
    decorator
    numpy
    pyyaml
    scipy
  ];

  # `@pytest.mark.usefixtures("aiida_profile_clean")` sits on top of
  # `@pytest.fixture` in tests/conftest.py, and pytest 9 refuses to collect it:
  #
  #   Failed: Marks cannot be applied to fixtures.
  #
  # A mark on a fixture has never done anything — pytest has warned about it
  # for years — so the clean profile upstream wanted was never being requested
  # either.  Making the fixture take `aiida_profile_clean` as an argument is
  # both the fix and what the mark was reaching for; the `unused-argument`
  # pylint suppression already on that line says the argument used to be there.
  #
  # Twice, because tests/test_entry_points.py has the same pair the other way
  # up — `@pytest.fixture` above `@pytest.mark.usefixtures(...)`.  Order makes
  # no difference to pytest; both are collection errors, and fixing only the
  # first turns a build failure into an identical build failure one module
  # later.
  #
  # The third file is a name collision rather than a deprecation.
  # `AddInputsWorkChain` has an input port called `inputs`, and aiida-core's
  # launchers now take `inputs` as their own second parameter —
  # `run_get_node(process, inputs=None, **kwargs)` — so a call that passes the
  # port as a keyword alongside others is rejected before the process sees it:
  #
  #   ValueError: Cannot specify both `inputs` and `kwargs`.
  #
  # The supported spelling is one dictionary, where a port named `inputs` is
  # just another key, so the two calls are rewritten to it.  This is worth
  # knowing outside the tests: anyone driving this workchain from Python hits
  # the same collision, and the same dictionary is the way out.
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail '@pytest.mark.usefixtures("aiida_profile_clean")' "" \
      --replace-fail \
        'def run_optimization():  # pylint: disable=unused-argument' \
        'def run_optimization(aiida_profile_clean):  # pylint: disable=unused-argument'

    substituteInPlace tests/test_entry_points.py \
      --replace-fail '@pytest.mark.usefixtures("aiida_profile_clean")' "" \
      --replace-fail \
        'def check_entrypoints():' \
        'def check_entrypoints(aiida_profile_clean):'

    substituteInPlace tests/wrappers/test_add_inputs_wrapper.py \
      --replace-fail \
        '    res, node = run_get_node(
            AddInputsWorkChain,
            sub_process=EchoDictValue,
            inputs={"x": orm.Float(1)},
            added_input_values=orm.List(list=[2.0]),
            added_input_keys=orm.List(list=["a:b.c"]),
        )' \
        '    res, node = run_get_node(
            AddInputsWorkChain,
            {
                "sub_process": EchoDictValue,
                "inputs": {"x": orm.Float(1)},
                "added_input_values": orm.List(list=[2.0]),
                "added_input_keys": orm.List(list=["a:b.c"]),
            },
        )' \
      --replace-fail \
        '    res, node = run_get_node(
            AddInputsWorkChain,
            sub_process=EchoDictValue,
            inputs={"x": orm.Float(1)},
            added_input_values=orm.Float(2),
            added_input_keys=orm.Str("a:b.c"),
        )' \
        '    res, node = run_get_node(
            AddInputsWorkChain,
            {
                "sub_process": EchoDictValue,
                "inputs": {"x": orm.Float(1)},
                "added_input_values": orm.Float(2),
                "added_input_keys": orm.Str("a:b.c"),
            },
        )'
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
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_optimize"
    "aiida_optimize.engines"
    "aiida_optimize.wrappers"
  ];

  meta = {
    description = "AiiDA plugin for running optimization algorithms";
    homepage = "https://github.com/greschd/aiida-optimize";
    # Apache 2.0 for the program, BSD-3 for one file.
    #
    # LICENSE.txt is the Apache 2.0 text and setup.json's `license` says
    # "Apache 2.0", as does the PyPI classifier.  ADDITIONAL_TERMS.txt calls
    # LICENSE.txt "GPLv3" in passing, which is stale wording rather than a
    # third license — the file it actually governs,
    # aiida_optimize/engines/_nelder_mead.py, is derived from SciPy's
    # optimize.py and carries the Enthought/SciPy BSD-3 notice.  That is what
    # the second entry is.
    #
    # A list rather than one license: ci.nix's `isBuildable` normalises either
    # shape and requires every entry to be free, which both of these are.
    license = with lib.licenses; [
      asl20
      bsd3
    ];
    maintainers = with lib.maintainers; [ berquist ];
  };
}
