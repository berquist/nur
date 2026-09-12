{
  lib,
  buildPythonPackage,

  # build-system
  setuptools,

  # dependencies
  dpdata,
  numpy,
}:

# dpdata-plugin-test — the one-file distribution that lives in `tests/plugin/`
# of the dpdata repository, whose entire body is three `register_data_type`
# calls for the custom data types `foo` and `bar`.  It exists so that dpdata's
# own suite can exercise the `dpdata.plugins` entry-point mechanism, and
# upstream's CI installs it with `uv pip install ./tests/plugin`.
#
# Twenty tests in `test_custom_data_type.py` round-trip those two types through
# deepmd raw, npy, hdf5 and npy/mixed.  Without this they fail on
# `KeyError: 'foo'`, and ../dpdata's `nativeCheckInputs` is the only consumer.
#
# **Importing the module is not a substitute for installing it, and that is the
# whole reason this is a derivation rather than a `-p` flag.**  The registration
# is a module-scope side effect, but `dpdata/system.py` folds the registry into
# `System.DTYPES` at *its* import time, guarded by the comment "Ensure all
# plugins have been loaded before executing this function".  Anything that
# imports the plugin from outside dpdata therefore runs too late: the plugin
# imports `dpdata.data_type`, which imports the `dpdata` package, which does the
# fold — and only then do the three `register_data_type` calls land, in a
# registry nothing will read again.  Going through the entry point is what puts
# them in the right order, because `dpdata/plugins/__init__.py` loads entry
# points *during* that same import.
#
# A `pytest -p dpdata_plugin_test` was tried first and left all twenty failing
# exactly as before, which is what the ordering above predicts.
buildPythonPackage {
  pname = "dpdata-plugin-test";

  # `0.0.0`, which is what `tests/plugin/pyproject.toml` declares statically and
  # therefore what lands in `.dist-info/METADATA`.  It has to match:
  # `pythonMetadataCheckPhase` compares the two and fails the build otherwise,
  # which is how the first attempt at this — `inherit (dpdata) version src`, on
  # the reasoning that the source *is* dpdata 1.1.0's — was caught.  The tie to
  # dpdata's tag is in `src` below, where it belongs.
  version = "0.0.0";
  inherit (dpdata) src;
  pyproject = true;
  __structuredAttrs = true;

  # The same source tree as ../dpdata, one directory down.  No second fetch:
  # `src` is inherited above, so this shares that store path rather than
  # downloading the repository twice.
  sourceRoot = "${dpdata.src.name}/tests/plugin";

  build-system = [ setuptools ];

  # The version is static, so nothing needs a pretend version — unlike ../dpdata,
  # which is setuptools-scm.
  #
  # **dpdata is taken with its check phase off, and that is a real cycle being
  # cut rather than a tidiness.**  This package declares dpdata, and dpdata's
  # check phase declares this package; nix cannot express that.  The override
  # makes the copy built *for this* one skip its tests, so the recursion stops
  # after one step.  It is the ../doped and ../shakenbreak situation with a
  # different remedy: there the requirement could simply be dropped, because the
  # import was function-local; here the plugin genuinely imports
  # `dpdata.data_type` at module scope.
  #
  # The cost is that the dpdata inside this derivation is a second store path.
  # It is small — a pure-Python wheel — and nothing but the entry-point metadata
  # of this package is used at dpdata's check time, so the two never meet in one
  # environment in a way that matters.
  dependencies = [
    (dpdata.overridePythonAttrs (_: {
      doCheck = false;
    }))
    numpy
  ];

  # No tests of its own — it *is* a test fixture.  Twelve lines, three calls.
  doCheck = false;

  # **`dpdata`, not `dpdata_plugin_test`, and that is not a typo.**  Importing
  # this module directly is a circular import and fails outright:
  #
  #   dpdata_plugin_test/__init__.py    from dpdata.data_type import ...
  #   dpdata/__init__.py                from .bond_order_system import ...
  #   dpdata/system.py                  import dpdata.plugins
  #   dpdata/plugins/__init__.py        plugin = ep.load()
  #   AttributeError: partially initialized module 'dpdata_plugin_test' has no
  #                   attribute 'ep' (most likely due to a circular import)
  #
  # The entry point names `dpdata_plugin_test:ep`, and by the time dpdata gets
  # round to loading it we are still inside that module's own first import, so
  # `ep` does not exist yet.  Nothing is wrong with the installed wheel — the
  # order is simply the one order that cannot work.
  #
  # `import dpdata` is the order that does, and it is a stronger check anyway:
  # it drives the entry point, which imports this module, which registers `foo`
  # and `bar`.  If the metadata were missing or malformed, dpdata would import
  # without them, and ../dpdata's twenty `test_custom_data_type.py` tests are
  # what catch that.
  pythonImportsCheck = [ "dpdata" ];

  meta = {
    description = "Entry-point plugin fixture from dpdata's own test suite";
    homepage = "https://github.com/deepmodeling/dpdata";
    license = lib.licenses.lgpl3Plus;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
