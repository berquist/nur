{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  monty,
  numpy,
  pydantic,
  pydantic-settings,
  pymatgen-core,
  requests,

  # tests
  pytestCheckHook,
}:

# A validator for VASP inputs and outputs against the Materials Project's own
# input sets.  The near-term reason it is here: emmet-core depends on it, and
# atomate2 and quacc depend on emmet-core.  See "Deferred packaging" in
# ../../AGENTS.md.
#
# It installs into `pymatgen/io/validation/` — a third distribution sharing the
# `pymatgen/` namespace with ../pymatgen-core and ../pymatgen.  All three are
# PEP 420 namespace packages with no `pymatgen/__init__.py`, and none of them
# ships a file the others also ship (`pymatgen/io/` has no `__init__.py`
# either), so `python3.withPackages` merges the three without
# pythonCatchConflictsPhase firing.
#
# Depends on `pymatgen-core` alone, matching upstream: the one module that
# reaches into the other half — `check_for_excess_empty_space.py`, which imports
# `pymatgen.analysis.local_env` — is dead code, referenced from nowhere and not
# collected by the suite.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-io-validation";
  version = "0.1.4";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "pymatgen-io-validation";
    tag = "v${finalAttrs.version}";
    hash = "sha256-FtXW8nLOcUdsH19v+yJE6W+vcoCy595aeOCLt+vjR2g=";
  };

  # The same versioningit hole ../qtoolkit and ../jobflow fall into:
  # `method = "git"` against a fetchFromGitHub tarball that has no repository,
  # and a `default-tag` that does not cover it because it only applies when the
  # repository exists and is untagged.  See ../qtoolkit/default.nix for why the
  # top-level `default-version` is the one that does, and why the table has to
  # be inserted ahead of the `vcs` sub-table rather than after.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${finalAttrs.version}"

    [tool.versioningit.vcs]'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # monty is not upstream's — it relies on pymatgen-core propagating it — but
  # `common.py`, `settings.py` and the conftest all `from monty import ...`
  # directly, so it is named here.  It resolves to the same derivation
  # pymatgen-core already propagates.
  dependencies = [
    monty
    numpy
    pydantic
    pydantic-settings
    pymatgen-core
    requests
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "pymatgen.io.validation" ];

  meta = {
    description = "Comprehensive I/O validator for electronic-structure calculations";
    homepage = "https://github.com/materialsproject/pymatgen-io-validation";
    changelog = "https://github.com/materialsproject/pymatgen-io-validation/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.bsd3Lbnl;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
