{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  scikit-build-core,
  setuptools-scm,
  pybind11,
  cmake,
  ninja,

  # native
  eigen,

  # dependencies
  numpy,
  pyyaml,
  scipy,

  # optional-dependencies
  phono3py,
  phonopy,
  spglib,
  symfc,

  # tests
  pytestCheckHook,
  ase,
  joblib,
  matplotlib,
}:

# pypolymlp — polynomial machine-learning potentials, with a C++ evaluator
# bound through pybind11.  Carried for ../phonopy's `pypolymlp` extra, which is
# what phonopy's `phonopy-mlpsscha` and `--pypolymlp` paths call.  nixpkgs has
# no copy at all, so this is an ordinary package rather than a backport.
#
# **The check inputs form a cycle with phonopy**, and it is cut on phonopy's
# side.  This suite needs phono3py at import — tests/conftest.py opens with
# `import phono3py` — and phonopy's and phono3py's own suites want pypolymlp for
# a dozen tests between them.  So those two take this package with
# `doCheck = false`, which drops the check inputs from the derivation and with
# them the edge back to phono3py; this one, with its suite, is the top-level
# attribute.  ../dpdata-plugin-test cuts its cycle the same way.
buildPythonPackage (finalAttrs: {
  pname = "pypolymlp";
  version = "0.22.2";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "sekocha";
    repo = "pypolymlp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/1eyvmwwM4bb6kxxiNp0WsVMbhX72eUjdCtpurRtMsY=";
  };

  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `[build-system] requires` names three PyPI wheels that exist only to put a
  # program or a header tree on a pip user's path: `cmake`, `pybind11-global`
  # and `eigen`.  Here those come from nixpkgs as a native input, pybind11's
  # CMake config and the `eigen` C++ package, and pypa build checks the list
  # before the backend loads — so the three are removed from it rather than
  # supplied.  `pythonRelaxDeps` only reaches the wheel's runtime metadata,
  # the same reason ../phono3py rewrites its nanobind pin here.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '    "cmake",' "" \
      --replace-fail '    "pybind11-global",' "" \
      --replace-fail '    "eigen",' ""
  '';

  build-system = [
    scikit-build-core
    setuptools-scm
    pybind11
  ];

  nativeBuildInputs = [
    cmake
    ninja
  ];

  buildInputs = [ eigen ];

  dontUseCmakeConfigure = true;

  dependencies = [
    numpy
    pyyaml
    scipy
  ];

  # Upstream's own extras, `tools` being the union of the other four.  Not
  # `rec`: every extra is named after the function argument it holds, and under
  # `rec` the attribute would win and contain itself — the trap ../parsl
  # describes at its own `optional-dependencies`.
  optional-dependencies =
    let
      extras = {
        symfc = [ symfc ];
        phonopy = [ phonopy ];
        phono3py = [ phono3py ];
        spglib = [ spglib ];
      };
    in
    extras // { tools = lib.concatLists (lib.attrValues extras); };

  # `ase`, `joblib` and `matplotlib` are imported by the package and its tests
  # without being declared anywhere; they are check inputs because the suite is
  # where they were found, not because they are test-only.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    joblib
    matplotlib
  ]
  ++ finalAttrs.passthru.optional-dependencies.tools;

  # The source tree has a `pypolymlp/` too, without the compiled `cxx/lib` that
  # CMake installs into the wheel, so it would shadow the installed copy.
  preCheck = ''
    rm -r src
  '';

  # Upstream marks its slowest tests `big` and skips them unless `--runbig` is
  # passed; left at that default.
  enabledTestPaths = [ "tests" ];

  pythonImportsCheck = [
    "pypolymlp"
    "pypolymlp.cxx.lib.libmlpcpp"
  ];

  meta = {
    description = "Polynomial machine learning potentials";
    homepage = "https://github.com/sekocha/pypolymlp";
    license = lib.licenses.bsd3;
    mainProgram = "pypolymlp";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
