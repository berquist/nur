{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,
  importlib-resources,
  jsonschema,
  numpy,
  packaging,
  python-dateutil,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pytest-timeout,
  pgtest,
  postgresql,
  ase,
  pymatgen,
  lammps,
  coreutils,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-lammps";
  version = "1.0.2-unstable-2025-01-07";
  pyproject = true;

  # Not fetchPypi: the sdist drops `tests/`, and this is the largest suite of
  # the new plugins.  See ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "aiidaplugins";
    repo = "aiida-lammps";
    rev = "d659a092f9a6934f4e14e2af5b72f529f5fe255f";
    hash = "sha256-BcKfMobiqfhlR+p4p6MAdO+5ejfMxq+poWnAoOLrifI=";
  };

  build-system = [ flit-core ];

  # aiida-core for the usual pre-release reason (../aiida-orca/default.nix).
  #
  # jsonschema is `jsonschema~=3.2.0` against nixpkgs' 4.26.0.  The library's
  # API is not the problem — src/aiida_lammps/validation/utils.py has the
  # package's only use of it, a single
  # `jsonschema.validate(schema=..., instance=...)`, whose signature is
  # unchanged.  What changed is the *default draft*; see postPatch below, which
  # is the other half of this relax.
  pythonRelaxDeps = [
    "aiida-core"
    "jsonschema"
  ];

  dependencies = [
    aiida-core
    importlib-resources
    jsonschema
    numpy
    packaging
    python-dateutil
  ];

  # Two rewrites.
  #
  # `filepath_executable="/bin/true"` in conftest.py, against a sandbox with
  # only /bin/sh.  See ../aiida-orca/default.nix.
  #
  # And distutils, which PEP 632 removed from the standard library in 3.12.
  # tests/utils.py imports it at module scope, so this is not one test failing
  # but the whole suite failing to collect:
  #
  #   tests/utils.py:5: in <module>
  #       import distutils.spawn
  #   E   ModuleNotFoundError: No module named 'distutils'
  #
  # `shutil.which` is what `distutils.spawn.find_executable` became — the
  # standard library's own replacement, and what upstream's neighbouring
  # branch in the same function already reaches for.  Adding setuptools to
  # resurrect the vendored distutils would work too, and would be carrying a
  # build-system dependency into the check phase to keep a dead import alive.
  #
  # The third is the other half of relaxing jsonschema.  lammps_schema.json
  # declares no `$schema`, so `jsonschema.validate` picks the newest draft it
  # knows — 2020-12 — and rejects the schema itself before it ever looks at the
  # data:
  #
  #   jsonschema.exceptions.SchemaError: [{'description': 'strain rates in the
  #   x direction', 'type': 'number'}, ...] is not of type 'object', 'boolean'
  #
  # That is the array form of `items`, which 2020-12 renamed `prefixItems`.  The
  # schema is not 2020-12 and never claimed to be: it spells its identifier
  # `id` rather than `$id`, which is draft-04.  Saying so out loud is the fix,
  # and draft-07 rather than draft-04 is the accurate answer — the file uses
  # `propertyNames` in twenty-odd places, a keyword draft-04 does not have and
  # would silently ignore, which would turn a validation error into a schema
  # that quietly checks less than it says.
  #
  # One line rather than a two-line insert, because JSON does not care and a
  # multi-line replacement in a Nix `''` string has its indentation rewritten
  # by the dedent.
  postPatch = ''
    substituteInPlace conftest.py \
      --replace-fail '"/bin/true"' '"${coreutils}/bin/true"'

    substituteInPlace tests/utils.py \
      --replace-fail 'import distutils.spawn' 'import shutil' \
      --replace-fail 'distutils.spawn.find_executable(executable)' 'shutil.which(executable)'

    substituteInPlace src/aiida_lammps/validation/schemas/lammps_schema.json \
      --replace-fail '"id": "#root",' \
        '"$schema": "http://json-schema.org/draft-07/schema#", "id": "#root",'
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  # nixpkgs installs the LAMMPS executable as `lmp`, with `lmp_serial` beside
  # it; conftest.py's `db_test_app` fixture defaults to the name `lammps` and
  # resolves it on PATH, so the runs would fail to find a code.  Upstream
  # provides this option for exactly that, which is better than patching the
  # default.
  #
  # Two list entries, not one string: pytestFlags reaches the hook through
  # `concatTo`, which word-splits — see the disabledTestMarks note in
  # ../fireworks/default.nix for what that does to an argument that has to stay
  # one word.  A flag and its value are two arguments, so this is the shape that
  # works.
  pytestFlags = [
    "--lammps-exec"
    "lmp"
  ];

  # Eight pytest-regressions references that encode the LAMMPS build they were
  # recorded against rather than anything this package does.  Two ways, both
  # visible in one diff:
  #
  #     warnings:
  #   - - 'WARNING: Using ''neigh_modify every 1 delay 0 check yes'' setting
  #       during minimization'
  #
  #     c_property_atom_all_aiida__1__:
  #   - - '-2.4702462298e-15'
  #   + - '-2.4424906542e-15'
  #
  # The first is a warning LAMMPS 22Jul2025 no longer emits during
  # minimization; the second is per-atom values that are zero to within
  # floating-point noise and differ in the last two digits.  `data_regression`
  # compares the serialised text exactly, so both are failures.
  #
  # Patching the references — which is what ../aiida-ase and
  # ../aiida-quantumespresso do for their stale ones — cannot work here: the
  # numbers are not a fixed new value to write down, they are whatever this
  # machine's LAMMPS and BLAS produce, and they would differ again on the next
  # one.  Nothing about the parser is being asserted that the other 57 tests do
  # not also cover.
  #
  # Node ids, not bare names, for the reason given at `pymatgenFor` in
  # ../../overlays/default.nix: an entry containing `::` is passed as
  # `--deselect`, which is exact, while a bare name becomes a `-k` expression.
  # Naming the function deselects all of its parametrizations.
  disabledTestPaths = [
    "tests/test_calculations.py::test_lammps_base"
    "tests/test_workflows.py::test_relax_workchain"
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-regressions
    pytest-timeout

    # conftest.py names `aiida.manage.tests.pytest_fixtures`, the deprecated
    # module, whose profile is a real PostgreSQL one.  See ../pgtest for why
    # postgresql is listed alongside it.
    pgtest
    postgresql

    # Two members of aiida-core's `atomic_tools` extra, which `dependencies`
    # cannot express.  tests/test_workflows.py compares structures through
    # `StructureData.get_pymatgen()`, and the four restart tests in
    # tests/test_calculations.py go the other way, through
    # `StructureData.get_ase()`:
    #
    #   ModuleNotFoundError: No module named 'ase'
    #
    # pymatgen is threaded in from the overlay rather than resolved through the
    # package set, because nixpkgs gates it off 3.13 — see `pymatgenFor` in
    # ../../overlays/default.nix.  ase has no such gate.
    ase
    pymatgen

    # tests/test_calculations.py and tests/test_workflows.py call
    # `run_get_node`, so LAMMPS really runs.
    #
    # This has to be threaded in from `final` by the overlay, and is the same
    # trap as aiida-core's `jq` — see the callPackage sites in
    # ../../overlays/default.nix.  nixpkgs has a `python313Packages.lammps`,
    # the Python binding, and pself wins over final inside a package-set
    # callPackage, so a defaulted argument here yields a package with no
    # bin/lmp.  The failure is not an evaluation error but
    #
    #   ValueError: lmp executable not found in PATH.
    #
    # out of tests/utils.py, after `shutil.which` comes back empty.
    lammps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_lammps"
    "aiida_lammps.calculations"
    "aiida_lammps.data"
    "aiida_lammps.parsers"
    "aiida_lammps.workflows"
  ];

  meta = {
    description = "AiiDA plugin for the LAMMPS molecular dynamics code";
    homepage = "https://github.com/aiidaplugins/aiida-lammps";
    changelog = "https://github.com/aiidaplugins/aiida-lammps/blob/master/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
