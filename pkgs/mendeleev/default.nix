{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  poetry-core,

  # dependencies
  colorama,
  deprecated,
  numpy,
  pandas,
  pint,
  pyfiglet,
  pygments,
  pydantic,
  sqlalchemy,

  # tests
  pytestCheckHook,
  pytest-xdist,
  bokeh,
  plotly,
  seaborn,
}:

# A Pythonic periodic table: element properties served out of a bundled SQLite
# database.  Carried for `lobsterpy[featurizer]`, whose `FeaturizeCharges`
# raises without it — so this restores `lobsterpy`'s `tests/featurize/` suite.
# Not re-exported: it stays reachable through `python313Packages`.
buildPythonPackage (finalAttrs: {
  pname = "mendeleev";
  version = "1.2.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "lmmentel";
    repo = "mendeleev";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/DNaQ/B3B0yHnOmbStKT5a2K+m3vnNjO4qd7vEKRQLA=";
  };

  # `[tool.poetry] version = "v1.2.0"` — the leading `v` is not PEP 440, and
  # poetry-core 2.x rejects it outright.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "v${finalAttrs.version}"' 'version = "${finalAttrs.version}"'
  '';

  build-system = [ poetry-core ];

  # Poetry caret pins that the channels here have all moved past — `pint ~0.24`
  # (0.25), `pyfiglet ~0.8` (1.0), `pandas ~2.1` (3.0).  mendeleev's use of each
  # is basic: `pint.Quantity` for unit-tagged properties, `pyfiglet` for one CLI
  # banner, ordinary DataFrame construction.
  pythonRelaxDeps = true;

  dependencies = [
    colorama
    deprecated
    numpy
    pandas
    pint
    pyfiglet
    pygments
    pydantic
    sqlalchemy
  ];

  # bokeh / plotly / seaborn back `mendeleev.vis`, which `test_imports.py` and
  # `test_vis.py` import.  pytest-xdist because `addopts` opens with `-n auto`.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    bokeh
    plotly
    seaborn
  ];

  pythonImportsCheck = [
    "mendeleev"
    "mendeleev.fetch"
    "mendeleev.ion"
  ];

  meta = {
    description = "Pythonic periodic table of elements";
    homepage = "https://github.com/lmmentel/mendeleev";
    changelog = "https://github.com/lmmentel/mendeleev/blob/v${finalAttrs.version}/docs/source/news.rst";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
