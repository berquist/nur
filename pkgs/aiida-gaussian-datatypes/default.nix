{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  aiida-core,
  cp2k-input-tools,
  click,
  tabulate,

  # tests
  pytestCheckHook,
  python,
}:

buildPythonPackage rec {
  pname = "aiida-gaussian-datatypes";
  version = "0.5.1";
  pyproject = true;

  # aiida-cp2k depends on this unbounded, so any recent release will do.
  #
  # Not fetchPypi: PyPI serves no sdist for 0.5.1 under either spelling, so
  # every mirror 404s — the same as ../cp2k-output-tools.  Note the owner is
  # dev-zero rather than aiidateam; this plugin has never lived under the
  # AiiDA organisation.
  src = fetchFromGitHub {
    owner = "dev-zero";
    repo = "aiida-gaussian-datatypes";
    tag = "v${version}";
    hash = "sha256-ZaifZ5hZNADTqt5Vfu/bQGjvT8NvPlX/cR2KBGCmn9E=";
  };

  # The fourteenth package on the deprecated fixture plugin, and the one the
  # first survey missed: that pass grepped the *derivations* for
  # `aiida.manage.tests.pytest_fixtures`, and this file's comments never
  # mentioned it even though its conftest names it.  Grep the sources, not the
  # prose.  See ../aiida-cp2k for the migration and ../aiida-diff for the
  # fixtures that went with it — `clear_database_before_test` is one of the five
  # `clear_*` variants replaced by `aiida_profile_clean`.
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def clear_database_auto(clear_database_before_test):' \
        'def clear_database_auto(aiida_profile_clean):'
  '';

  build-system = [ setuptools ];

  pythonRelaxDeps = [ "aiida-core" ];

  # setup.json's install_requires is `aiida-core` and `cp2k-input-tools`.
  # cp2k-**input**-tools, not the output one this used to list: they are
  # unrelated projects by the same author, and the source imports only the
  # former — `from cp2k_input_tools.basissets import BasisSetData` in
  # basisset/data.py, and the matching pseudopotentials import.
  #
  # click and tabulate are undeclared upstream but genuinely imported, by the
  # CLI and the listing code respectively.
  dependencies = [
    aiida-core
    cp2k-input-tools
    click
    tabulate
  ];

  # test_basisset_reachable and test_pseudo_reachable each run
  # `subprocess.check_output(["verdi", "data", "gaussian.<thing>", "--help"])`
  # and assert that the output has a usage line — that is, they check that this
  # plugin's data classes are reachable from the *installed* verdi rather than
  # only through click's test runner.  Two things have to be true for that, and
  # neither is arranged by depending on aiida-core in the ordinary way.
  #
  # PATH is the first.  aiida-core is a runtime dependency, so it lands at host
  # offset, and stdenv only adds `$pkg/bin` to PATH for build-offset inputs —
  # hence the second, build-offset entry in nativeCheckInputs below.  It is the
  # same derivation, so it costs nothing but the PATH entry.
  #
  # PYTHONPATH is the second.  verdi discovers `verdi data gaussian.basisset`
  # by scanning sys.path for dist-info metadata declaring an `aiida.data` entry
  # point, and this package's own site-packages is not on it during the check.
  # pythonImportsCheckPhase happens to export exactly this a few lines earlier
  # in preDistPhases, which is why the failure is PATH-shaped and not
  # entry-point-shaped, but that is its side effect and not a promise.
  preCheck = ''
    export PATH="$out/bin:$PATH"
    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"
  '';

  nativeCheckInputs = [
    pytestCheckHook
    aiida-core
  ];

  # Both `test_validation_empty` functions query `filters={'attributes.element':
  # None}`, and **the supported fixture plugin's profile is `core.sqlite_dos`,
  # where that filter is not implemented**:
  #
  #   TypeError: Unsupported type <class 'NoneType'> for SQLite query:
  #   aliased(DbNode).attributes.['element'] == None
  #
  # This is the price of the migration rather than a defect in this package —
  # the deprecated plugin gave every plugin a PostgreSQL profile, and psql_dos
  # handles the filter.  It is aiida-core's gap, and aiida-core knows: the
  # branch is sitting commented out in `storage/sqlite_zip/orm.py`, above
  # `_cast_json_type`, with the reason it was left open —
  #
  #   # to-do: non-existent keys also equate to json_type null, so should check
  #   # it exists also
  #   # if value is None:
  #   #     return func.json_type(database_entity) == 'null'
  #
  # Writing that here would be implementing something upstream deliberately
  # stopped short of, and getting the missing-key case wrong turns a failing
  # test into a silently wrong query.  Two of thirty, both of them about a
  # validation message rather than about storage.  The other way out is giving
  # this one package a psql_dos profile back, which is a conftest override and
  # the pgtest/postgresql pair returning for it alone.
  disabledTests = [ "test_validation_empty" ];

  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [ "aiida_gaussian_datatypes" ];

  meta = {
    description = "AiiDA data plugin for Gaussian basis sets and pseudopotentials";
    homepage = "https://github.com/dev-zero/aiida-gaussian-datatypes";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
