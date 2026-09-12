{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  typeguard,

  # tests
  pytestCheckHook,
  ipython,
  jsonschema,
  pyyaml,
}:

# dargs — DeepModeling's argument definition, checking and normalisation
# library, and the documentation generator that goes with it.  Here for
# ../deepmd-kit, which declares it as a core dependency and uses it for the
# whole of `deepmd.utils.argcheck`.  Internal, not re-exported.
buildPythonPackage (finalAttrs: {
  pname = "dargs";
  version = "0.5.1";
  pyproject = true;
  __structuredAttrs = true;

  # An actual tagged release, which is a change from the rest of this cluster:
  # vise, pydefect, doped and shakenbreak are all pinned hundreds of commits
  # past a stale tag.  DeepModeling tags properly.
  src = fetchFromGitHub {
    owner = "deepmodeling";
    repo = "dargs";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tZkSYB8nmx4QOuhi8/eXjaL0ZXsvCfRZ2qZqIft726I=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # Pinned rather than left to setuptools-scm, whose failure mode here is a
  # `0.1.dev1` version rather than an error — the same reason ../cmcrameri and
  # ../sella pin it.
  #
  # Upstream would in fact get this right on its own: `.git_archival.txt` is
  # marked `export-subst`, so GitHub's tarball carries `describe-name: v0.5.1`
  # and setuptools-scm reads the version straight out of it.  That is worth
  # knowing about and not worth depending on, since it makes the version a
  # property of how the tarball was produced rather than of this file.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # The only runtime requirement.  `typing_extensions` is declared upstream but
  # guarded — `try: from typing import get_origin` with the import as its
  # `except ImportError` branch — and 3.13 takes the first arm, so it is dead
  # weight here.
  dependencies = [ typeguard ];

  # All three are upstream's `test` extra.  jsonschema is what `test_json_schema`
  # validates against, IPython is imported at module scope by `dargs/notebook.py`
  # (which `test_notebook` exercises), and pyyaml backs the lazy `import yaml`
  # in `_refs.py` that the `yaml` extra advertises.
  nativeCheckInputs = [
    pytestCheckHook
    ipython
    jsonschema
    pyyaml
  ];

  enabledTestPaths = [ "tests" ];

  # `dargs.sphinx` is left out deliberately: it imports sphinx and docutils at
  # module scope, both of which upstream declares under `typecheck` rather than
  # as dependencies, and no test touches it.  It is a Sphinx extension a
  # documentation build opts into, not part of the library — the same shape as
  # ../dbstep's `dbstep.graph`.
  #
  # `dargs.notebook` is in, because IPython is a check input and the module is
  # what `test_notebook` covers.
  pythonImportsCheck = [
    "dargs"
    "dargs.check"
    "dargs.cli"
    "dargs.dargs"
    "dargs.json_schema"
    "dargs.notebook"
  ];

  meta = {
    description = "Argument processing for the DeepModeling projects";
    homepage = "https://github.com/deepmodeling/dargs";
    changelog = "https://github.com/deepmodeling/dargs/releases/tag/v${finalAttrs.version}";
    # `Only`, not `Plus`: there is no SPDX identifier and no "or any later
    # version" grant anywhere in the tree — just the bare LGPL-3.0 text and a
    # `LGPLv3` trove classifier, which is the one without the trailing `+`.
    # ../deepmd-kit, its one dependant, does say `LGPL-3.0-or-later` for itself.
    license = lib.licenses.lgpl3Only;
    mainProgram = "dargs";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
