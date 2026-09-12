{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  pymatgen-core,

  # tests
  pytestCheckHook,
  hypothesis,
  matplotlib,
}:

# Re-gridding of periodic volumetric quantum chemistry data (CHGCAR and the
# like).  The distribution is `mp-pyrho`, the import is `pyrho`.  Carried for
# `pymatgen-analysis-defects`, which lists `mp-pyrho>=0.4.4` — and through it for
# `emmet-core`'s defects tests.  Not re-exported: its one dependant here reaches
# it through `python313Packages`.
buildPythonPackage (finalAttrs: {
  pname = "mp-pyrho";
  version = "0.5.1-unstable-2026-05-11";
  pyproject = true;
  __structuredAttrs = true;

  # A commit rather than the v0.5.1 tag, six behind it: the tag predates
  # `cf091c5` "Update import" (a pymatgen-core split fixup in charge_density.py)
  # and the `requires-python` bump to 3.11.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pyrho";
    rev = "58c5bc06834143a25c72fd3eadd0baa23e7ce749";
    hash = "sha256-4Hno8r5zRgPCoYuLrwW2AmmVeOp5F7qahol6DC9y/J4=";
  };

  # setuptools_scm against a fetchFromGitHub tarball with no repository — same as
  # ../maggma.  The `-unstable-` suffix is a nixpkgs convention rather than a
  # PEP 440 version, so only the part before the first dash goes in.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [ pymatgen-core ];

  # matplotlib because tests/conftest.py imports `matplotlib.pyplot` at module
  # scope; hypothesis for the property tests.
  nativeCheckInputs = [
    pytestCheckHook
    hypothesis
    matplotlib
  ];

  pythonImportsCheck = [
    "pyrho"
    "pyrho.charge_density"
  ];

  meta = {
    description = "Tools for re-gridding periodic volumetric quantum chemistry data";
    homepage = "https://github.com/materialsproject/pyrho";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
