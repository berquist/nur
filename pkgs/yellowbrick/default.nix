{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  fetchurl,
  unzip,

  # build-system
  setuptools,

  # dependencies
  cycler,
  matplotlib,
  numpy,
  scikit-learn,
  scipy,

  # tests
  pytestCheckHook,
  nltk,
  pandas,
  pytest-flakes,
  umap-learn,
}:

# yellowbrick — scikit-learn model diagnostics drawn as matplotlib figures:
# classification reports, elbow and silhouette plots, residuals, learning
# curves, feature rankings.  A "visualizer" is an estimator whose `show()`
# produces a plot rather than a prediction.
#
# Here for `fairchem-applications-ocx`, which is one of the two remaining
# fairchem distributions with a gap in nixpkgs, and for nothing else.  See
# "Deferred packaging" in ../../AGENTS.md.  Internal, not re-exported.
let
  # The eleven datasets `yellowbrick.datasets` downloads from S3 on first use.
  # Without them, 163 of the suite's 862 tests end in
  # `URLError: Temporary failure in name resolution` — and the five
  # `tests/test_text` modules call a loader at *module* scope, so that is a
  # collection error and fatal to the whole run rather than to themselves.
  #
  # **The hashes come out of the source tree, not a build.**
  # `yellowbrick/datasets/manifest.json` carries a URL and a SHA-256 signature
  # for each archive — upstream uses the signature to verify its own download —
  # so the SRI hash is `sha256-` plus that hex re-encoded as base64, derivable
  # with no clone, no network and no failed build to read the answer off.  That
  # is unusual and worth knowing: `scripts/offline-src-hash.sh` cannot answer
  # for a `fetchurl`, and here it does not have to.
  #
  # Nothing is rehosted.  Each archive is fetched from upstream's own URL at
  # build time, exactly as the library would fetch it at run time; the
  # difference is only that Nix does it once, checks the hash, and keeps it.
  datasets =
    lib.mapAttrs
      (
        name: hash:
        fetchurl {
          url = "https://yb-data-lake.s3.us-east-2.amazonaws.com/yellowbrick/v1.0/${name}.zip";
          inherit hash;
        }
      )
      {
        bikeshare = "sha256-TtB6kpzL4BcTCRKeat2hxDkBkDhd1gAbqe7MeVoh7vI=";
        concrete = "sha256-WAevLwThTkB/YeZqTz2vkQNhqZu1BSgJCWtH08zN/Ao=";
        credit = "sha256-LG9YIcQDnXDpAcwHnRQE9vScPWgVhxIxxANIppriZXM=";
        energy = "sha256-F07KPNgeiI/EFsAG3nfb5fidZDsgMZkCoDYuLxlyo04=";
        game = "sha256-znmdHFX88ZhaAt702FZyrIbAIvj3r+++QrIDZPukfXo=";
        hobbies = "sha256-YRTjL0a63fBJoY+wW60++pj05qD+hwZslAcVQcsekG8=";
        mushroom = "sha256-95/bwzsBLavQao88swB9JEtqqyLUE1i5rtp0QXyR8wA=";
        nfl = "sha256-SYnGaBjqGCF+4P46WZMrljvWWGmSjBQHWlxQNmy4Hh8=";
        occupancy = "sha256-CzkDh1hFhqBfRcfaYQ/ar4kixZVINPMjrjSRNzlOYlM=";
        spam = "sha256-AAMJrCthCQowAd4+JipfUxlwi7QnkcYtFaCKL598swo=";
        walking = "sha256-ejZhWXi8O7dKLp1d4haBViG9N/akLGXT/CiyQrTW4EA=";
      };
in
buildPythonPackage (finalAttrs: {
  pname = "yellowbrick";
  version = "1.5";
  pyproject = true;
  __structuredAttrs = true;

  # v1.5 is upstream's newest release, from 2022, and `main` has not moved
  # since.  Note that `develop` is the default branch and is *behind* the tags,
  # so `git describe` on a fresh clone answers v1.2 — take the tag, not HEAD.
  src = fetchFromGitHub {
    owner = "DistrictDataLabs";
    repo = "yellowbrick";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Zdh2AFt7JRALAtBf3fFnp6C5JY7x37LDCqjeF47QReg=";
  };

  # Two unrelated repairs, both consequences of packaging a 2022 release
  # against current dependencies.  See the patch itself for the reasoning; in
  # short, `np.string_` and `np.unicode_` were removed in NumPy 2, and the 341
  # image-comparison tests hold PNGs rendered by matplotlib 3.4.2 against a
  # tolerance of 0.01 of a colour value.
  patches = [ ./numpy2-and-baseline-images.patch ];

  # A third consequence of the same age, and this one is fatal on import rather
  # than at test time: `yellowbrick/style/{colors,rcmod}.py` both open with
  #
  #   from distutils.version import LooseVersion
  #   mpl_ge_150 = LooseVersion(mpl.__version__) >= "1.5.0"
  #
  # and Python removed `distutils` in 3.12, so importing `yellowbrick` at all
  # raises `ModuleNotFoundError: No module named 'distutils'`.
  #
  # The flag guards one branch in each file, and matplotlib 1.5 is from 2015 —
  # nixpkgs has 3.x — so the question it asks has exactly one answer now.
  # Setting it to `True` rather than reaching for `packaging.version` keeps the
  # dependency list honest: this needs no version comparison at runtime, it
  # needs the comparison deleted.  Same call as ../vise, which deletes two dead
  # `distutils` imports for the same reason.
  #
  # Three more removals of the same kind follow, each costing tests rather than
  # the import:
  #
  # `matplotlib.cm.get_cmap` went in matplotlib 3.9, and `mpl.colormaps[name]`
  # is its replacement — 39 failures across seven modules.  The lookup raises
  # `KeyError` where `get_cmap` raised `ValueError`, and `resolve_colors`
  # deliberately catches the latter to re-raise it as a `YellowbrickValueError`,
  # so the `except` clause is widened in the same breath.  Without that, "an
  # unknown colormap name is an error a caller can catch" would quietly stop
  # being true.
  #
  # `numpy.in1d` went in NumPy 2.0, replaced by `np.isin` — three failures.
  #
  # `tests/test_style/test_colors.py` calls the removed matplotlib function
  # itself, three times, so the test file is patched too.  Its `from matplotlib
  # import cm` exists for those three calls and nothing else, so it becomes a
  # plain `import matplotlib as mpl` — the name `mpl` is already in scope there
  # through `from yellowbrick.style.colors import *`, but importing it outright
  # is clearer than relying on what a star import happens to re-export.
  postPatch = ''
    substituteInPlace yellowbrick/style/colors.py yellowbrick/style/rcmod.py \
      --replace-fail 'from distutils.version import LooseVersion' "" \
      --replace-fail 'mpl_ge_150 = LooseVersion(mpl.__version__) >= "1.5.0"' 'mpl_ge_150 = True'

    substituteInPlace yellowbrick/style/colors.py \
      --replace-fail 'colormap = cm.get_cmap(colormap)' 'colormap = mpl.colormaps[colormap]' \
      --replace-fail 'except ValueError as e:' 'except (KeyError, ValueError) as e:'

    substituteInPlace yellowbrick/features/base.py \
      --replace-fail \
        'self._colors = mpl.cm.get_cmap(self.colormap)' \
        'self._colors = mpl.colormaps[self.colormap]'

    substituteInPlace yellowbrick/utils/helpers.py \
      --replace-fail \
        'np.in1d(feature_cols, ndarray_columns)' \
        'np.isin(feature_cols, ndarray_columns)'

    substituteInPlace tests/test_style/test_colors.py \
      --replace-fail 'from matplotlib import cm' 'import matplotlib as mpl' \
      --replace-fail 'cm.get_cmap("nipy_spectral")' 'mpl.colormaps["nipy_spectral"]'
  '';

  build-system = [ setuptools ];

  # matplotlib writes a font cache on first import, and with no writable HOME it
  # falls back to a temporary directory with a warning on every invocation.
  # `preBuild` rather than `preCheck`, because `pythonImportsCheck` imports
  # matplotlib through `yellowbrick.style` in a later phase than the tests.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # `setup.py` reads these out of requirements.txt rather than declaring them.
  dependencies = [
    cycler
    matplotlib
    numpy
    scikit-learn
    scipy
  ];

  # The three optional test dependencies upstream's tests/requirements.txt
  # marks as such: nltk for the text visualizers, pandas for the DataFrame
  # paths through nearly every visualizer, and umap-learn for
  # `yellowbrick.text.umap_vis`.  All three are in nixpkgs, and each would
  # otherwise turn a body of tests into skips.
  #
  # pytest-flakes is needed even though `--flakes` is not passed: `tests/
  # conftest.py` does `from pytest_flakes import FlakesItem` at module scope,
  # and a conftest that cannot be imported takes the whole session with it
  # before a single test is collected.  It uses the name for one `isinstance`
  # check in a reporting hook — with the flag off, nothing is ever an instance
  # of it, so installing the plugin costs nothing and runs no lint.  Same shape
  # as ../matplotlib-label-lines, which needs pytest-mpl for a marker it never
  # exercises.
  nativeCheckInputs = [
    pytestCheckHook
    nltk
    pandas
    pytest-flakes
    umap-learn
    unzip
  ];

  # `BaseDataset.__init__` downloads only `if not dataset_exists(...)`, so the
  # whole of the wiring is putting the data where `get_data_home` looks.
  #
  # That is `yellowbrick/datasets/fixtures` inside the package — the source
  # copy, which is what the tests import: pytest runs from the source root and
  # `prepend` import mode puts it ahead of $out.  **Not** `$YELLOWBRICK_DATA`,
  # which `get_data_home` would also honour: `tests/test_datasets/test_path.py`
  # asserts that the default is the in-package directory, so setting the
  # variable buys the same data and costs a legitimate test.
  #
  # Both halves of upstream's own download layout are reproduced, because both
  # are checked.  `download_data` writes `<data_home>/<name>.zip` and then
  # `zf.extractall(path=data_home)`, and `tests/test_datasets/test_loaders.py`
  # asserts the archive is still there *and* that its SHA-256 matches the
  # manifest — so extracting alone left eleven tests failing with "dataset
  # archive does not match signature".
  preCheck = ''
    fixtures="$PWD/yellowbrick/datasets/fixtures"
    mkdir -p "$fixtures"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: archive: ''
        cp ${archive} "$fixtures/${name}.zip"
        unzip -q ${archive} -d "$fixtures"
      '') datasets
    )}
  '';

  # Upstream's `addopts` is `--verbose --cov=yellowbrick --flakes --spec
  # --cov-report=xml --cov-report term`, which wants pytest-cov, pytest-flakes
  # and pytest-spec.  nixpkgs has all three, and the options are dropped anyway:
  # `--cov` writes coverage output that is thrown away, and `--flakes` runs
  # pyflakes over the source *as tests*, so a lint finding in a 2022 codebase
  # would register as a test failure.  Neither says anything about whether the
  # library works.  Clearing the ini value is the same fix ../disk-objectstore
  # and ../aiida-core use.
  #
  # Note that dropping `--flakes` does not drop the *plugin* — see the
  # nativeCheckInputs note above for why the conftest needs it importable
  # regardless.
  #
  # Note also `python_files = tests/*`, which is why `enabledTestPaths` names
  # the directory rather than a glob: every file under it is a test module by
  # upstream's own configuration.
  pytestFlags = [ "--override-ini=addopts=" ];

  enabledTestPaths = [ "tests" ];

  # With the datasets in place the suite collects 1137 tests, and 307 of them
  # fail.  **243 of those 307 are one thing**: scikit-learn 1.6 removed the
  # `_estimator_type` attribute in favour of `__sklearn_tags__()`, and
  # `yellowbrick/utils/types.py` decides what an estimator is with
  #
  #   getattr(estimator, "_estimator_type", None) == "classifier"
  #
  # so `is_classifier`, `is_regressor` and `is_clusterer` now answer False for
  # everything, and every visualizer that gates on them raises
  # `YellowbrickTypeError: This estimator is not a classifier`.
  #
  # That is an upstream port rather than a packaging fix, and the reason is in
  # the tests: they require the predicates to work on a *class*, an instance, a
  # `Pipeline` and a visualizer that merely wraps an estimator — four different
  # paths, only one of which sklearn's own `is_classifier` covers.  See
  # ../../docs/TODO.md for the analysis; it is not attempted here because
  # nothing in this repository depends on yellowbrick, and a forty-line
  # behavioural patch written blind against a suite this old is how a package
  # acquires bugs of its own.
  #
  # The remaining 53 failures are the same story in smaller pieces, all of them
  # a 2022 release meeting 2026 dependencies: `Axes.stem(use_line_collection=)`
  # and `np.matrix` gone, `CountVectorizer.get_feature_names` renamed,
  # liblinear's multiclass support dropped, NumPy refusing to stack a generator,
  # and six tests calling `self.fail` on a class that is not a `TestCase`.
  #
  # So: the thirty modules that hold those 307 failures are excluded, and 606
  # tests still run.  Two more are excluded for reasons of their own —
  # `test_download.py`, whose subject *is* the network fetch ("requires
  # Internet connection!", says its docstring), and `test_postag.py`, which
  # wants NLTK's own corpora rather than anything in `manifest.json`.
  disabledTestPaths = [
    "tests/test_classifier/test_base.py"
    "tests/test_classifier/test_class_prediction_error.py"
    "tests/test_classifier/test_classification_report.py"
    "tests/test_classifier/test_confusion_matrix.py"
    "tests/test_classifier/test_prcurve.py"
    "tests/test_classifier/test_rocauc.py"
    "tests/test_classifier/test_threshold.py"
    "tests/test_cluster/test_base.py"
    "tests/test_cluster/test_elbow.py"
    "tests/test_cluster/test_icdm.py"
    "tests/test_cluster/test_silhouette.py"
    "tests/test_contrib/test_classifier/test_boundaries.py"
    "tests/test_contrib/test_prepredict.py"
    "tests/test_contrib/test_wrapper.py"
    "tests/test_datasets/test_download.py"
    "tests/test_features/test_base.py"
    "tests/test_features/test_manifold.py"
    "tests/test_features/test_rankd.py"
    "tests/test_meta.py"
    "tests/test_model_selection/test_importances.py"
    "tests/test_pipeline.py"
    "tests/test_regressor/test_alphas.py"
    "tests/test_regressor/test_influence.py"
    "tests/test_regressor/test_prediction_error.py"
    "tests/test_regressor/test_residuals.py"
    "tests/test_style/test_colors.py"
    "tests/test_text/test_dispersion.py"
    "tests/test_text/test_freqdist.py"
    "tests/test_text/test_postag.py"
    "tests/test_utils/test_types.py"
  ];

  pythonImportsCheck = [
    "yellowbrick"
    "yellowbrick.classifier"
    "yellowbrick.cluster"
    "yellowbrick.features"
    "yellowbrick.model_selection"
    "yellowbrick.regressor"
    "yellowbrick.target"
    "yellowbrick.text"
  ];

  meta = {
    description = "Visual analysis and diagnostic tools for scikit-learn";
    homepage = "https://github.com/DistrictDataLabs/yellowbrick";
    changelog = "https://github.com/DistrictDataLabs/yellowbrick/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
