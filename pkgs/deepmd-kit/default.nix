{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  cmake,
  ninja,

  # build-system
  scikit-build-core,
  dependency-groups,
  hatch-fancy-pypi-readme,
  packaging,
  setuptools-scm,

  # dependencies
  array-api-compat,
  ase,
  dargs,
  einops,
  h5py,
  lmdb,
  mendeleev,
  ml-dtypes,
  msgpack,
  numpy,
  pyyaml,
  scipy,
  torch,
  wcmatch,

  # optional-dependencies
  dpdata,
  e3nn,
  rdkit,
  scikit-learn,
}:

# DeePMD-kit — deep-learning interatomic potentials, and `matcalc`'s `deepmd`
# extra, which is the last matcalc backend not behind NVIDIA's
# `nvalchemi-toolkit-ops` wall.  Internal, not re-exported: matcalc is its only
# dependant here.
#
# The name is one of this repo's dist/import splits: the distribution is
# `deepmd-kit`, the module is `deepmd`, and the console script is `dp`.
buildPythonPackage (finalAttrs: {
  pname = "deepmd-kit";
  version = "3.2.0";
  pyproject = true;
  __structuredAttrs = true;

  # An actual release tag, six commits behind the clone's master.  Unlike the
  # rest of the defects cluster there is no reason to go past it — DeepModeling
  # tags often and the tag is current.
  src = fetchFromGitHub {
    owner = "deepmodeling";
    repo = "deepmd-kit";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2uiS4g96g3LMuxY2TLFPU7h7w9WEJYj9gA3VUeJtJg0=";
  };

  # **The three switches that decide what this package is.**
  #
  # `DP_VARIANT` is already `cpu` by default, but it is spelled out because the
  # alternatives are `cuda` and `rocm` and a silent default is a poor place to
  # keep that decision.
  #
  # The two backend switches both default to *on*, and both are turned off.
  # That is what keeps this from being a CMake build against libtorch or
  # libtensorflow: with them off, `source/CMakeLists.txt` skips `op/tf/` and
  # `op/pt/` and builds only `lib/` (plain C++) and `config/`.  Turning all
  # backends off is explicitly supported — the guard at the end of that file
  # errors only when `BUILD_PY_IF` is *also* false, and scikit-build-core sets
  # it true.
  #
  # What is lost is `libdeepmd_op_pt.so`, and it is much less than it sounds.
  # `deepmd/pt/cxx_op.py` ends with `ENABLE_CUSTOMIZED_OP = load_library(...)`,
  # a plain boolean that comes back false when the library is absent, and the
  # descriptor modules install Python fallbacks behind it.  Exactly one thing
  # requires it: `dp compress`, which raises with a message naming the library.
  # `deepmd.calculator.DP` — inference, and the whole of what matcalc asks for —
  # does not consult it at all.  The other two readers are the version banner in
  # `pt/entrypoints/main.py` and the *Paddle* backend's repformers.
  #
  # Building the ops would mean `find_package(Torch REQUIRED)`, a CXX11-ABI
  # match against nixpkgs' torch and the CUDA-toolkit discovery bypass at the
  # top of that file.  Worth doing if a profile ever says so; not worth it to
  # make inference work, which is what this is for.
  #
  # The fourth is unrelated to the backends: the `setuptools_scm` provider below
  # has no repository to read from, and `[[tool.scikit-build.generate]]` bakes
  # whatever it decides into `deepmd/_version.py`.  Pinning it is the same call
  # ../dargs and ../cmcrameri make, and for the same reason — the failure
  # without it is a wrong version rather than an error.
  env = {
    DP_VARIANT = "cpu";
    DP_ENABLE_TENSORFLOW = "0";
    DP_ENABLE_PYTORCH = "0";
    SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;
  };

  # The build backend is upstream's own — `backend-path = ["."]` and
  # `build-backend = "backend.dp_backend"` — a wrapper that computes the CMake
  # arguments from the environment above and then hands off to
  # scikit-build-core.
  #
  # Only the first three appear in `[build-system] requires`.  The other two are
  # not written down anywhere in this file's dependencies: `[[tool.dynamic-metadata]]`
  # names two scikit-build-core *providers*, `scikit_build_core.metadata.setuptools_scm`
  # for the dynamic `version` and `...fancy_pypi_readme` for the dynamic
  # `readme`, and scikit-build-core resolves those into the list it returns from
  # `get_requires_for_build_wheel`.  Reading the backend's imports does not find
  # them; the build says so plainly instead.
  #
  # `get_requires_for_build_wheel` also appends `find_tensorflow()[1]` and
  # `find_pytorch()[1]`, which are empty here precisely because both backends
  # are off above — that is the switch working as intended.
  build-system = [
    scikit-build-core
    dependency-groups
    packaging

    hatch-fancy-pypi-readme
    setuptools-scm
  ];

  # cmake and ninja are driven by scikit-build-core rather than by the generic
  # cmake hook, so the configure phase has to be left alone — the usual pairing
  # for a scikit-build-core package.
  nativeBuildInputs = [
    cmake
    ninja
  ];
  dontUseCmakeConfigure = true;

  # Upstream's core `dependencies`, less `typing_extensions` and
  # `importlib_metadata`, which are both guarded on Python versions far below
  # this one.  `mendeleev` was already here for `lobsterpy[featurizer]`;
  # `dargs` is the one that had to be packaged, ../dargs.
  #
  # Two are added that upstream does not declare:
  #
  #   torch — no backend is a *declared* dependency, because upstream leaves the
  #   choice between TensorFlow, PyTorch, JAX and Paddle to the installer.  But
  #   a deepmd with no backend cannot evaluate a model at all, matcalc's
  #   `DPA3-LAM-2025.3.14` is a PyTorch model, and `deepmd/pt/` is the tree this
  #   build keeps.  So the choice is made here rather than left to fail at
  #   model-load time.
  #
  #   ase — `deepmd/calculator.py` imports it at module scope and upstream
  #   declares it under the `test` extra only.  That module *is* the matcalc
  #   entry point (`from deepmd.calculator import DP`), so without it the one
  #   thing this package is here for raises ImportError.  The fifth package in
  #   this cluster with an undeclared module-scope import, after vise, pydefect,
  #   doped and shakenbreak.
  dependencies = [
    array-api-compat
    ase
    dargs
    einops
    h5py
    lmdb
    mendeleev
    ml-dtypes
    msgpack
    numpy
    packaging
    pyyaml
    scipy
    torch
    wcmatch
  ];

  # `dpa-adapt`, the collective-variable adapter, and the only one of upstream's
  # extras whose members are all packaged.  Its six are scikit-learn, dpdata,
  # torch, ase, rdkit and e3nn — torch and ase are already dependencies above,
  # and ../dpdata is the one that had to be packaged for it.
  #
  # The others stay out: `test` wants `dpgui` and `nvalchemi-toolkit`, `docs` is
  # a Sphinx tree, and the backend extras want the TensorFlow and Paddle builds
  # that `env` above switches off.
  #
  # Costs this build nothing — `doCheck = false` below, so nothing here is a
  # check input.
  optional-dependencies = {
    dpa-adapt = [
      dpdata
      e3nn
      rdkit
      scikit-learn
    ];
  };

  # Not run, and this one is not a close call.  `source/tests/` is organised by
  # backend — `tf/`, `pt/`, `pd/`, `jax/` — and `consistent/` exists precisely
  # to cross-check the backends against each other, so most of it asks for the
  # two that are deliberately off above.  What is left needs `dpgui` and
  # `array_api_strict`, neither of which is packaged, and `tests/common` reaches
  # for torch and jax in the same breath.  (`dpdata` and `e3nn` were on that
  # list too and are packaged now — ../dpdata and nixpkgs' — so the gap is
  # smaller than it was, though the backends remain the real obstacle.)
  #
  # `pythonImportsCheck` carries the weight instead, and it is not a formality
  # here: the same check is what caught ../vise shipping a console script that
  # could not start.  It names the calculator that matcalc imports, the argument
  # tree that ../dargs exists for, and `deepmd.pt` — the backend whose custom-op
  # library this build leaves out, so that its Python fallback path is exercised
  # at least as far as importing.
  doCheck = false;

  pythonImportsCheck = [
    "deepmd"
    "deepmd.calculator"
    "deepmd.infer"
    "deepmd.pt"
    "deepmd.utils.argcheck"
  ];

  meta = {
    description = "Deep learning package for many-body potential energy representation";
    homepage = "https://github.com/deepmodeling/deepmd-kit";
    changelog = "https://github.com/deepmodeling/deepmd-kit/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.lgpl3Plus;
    mainProgram = "dp";
    maintainers = with lib.maintainers; [ berquist ];
    # Upstream's own classifiers are Linux and Windows only, and the CMake path
    # below `source/lib/` has not been tried on Darwin from here.
    platforms = lib.platforms.linux;
  };
})
