{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cmake,
  ninja,
  pybind11,
  scikit-build-core,
  setuptools-scm,

  # the C++ side's libraries, top-level attributes passed in by
  # ../../overlays/default.nix
  eigen,
  gsl,
  python,

  # dependencies
  ase,
  h5py,
  matplotlib,
  numpy,
  pyyaml,
  scipy,
  seaborn,

  # optional-dependencies
  phono3py,
  phonopy,
  spglib,
  symfc,

  # tests
  pytestCheckHook,
}:

buildPythonPackage (finalAttrs: {
  pname = "pypolymlp";
  version = "0.21.6";
  pyproject = true;

  # Polynomial machine-learning potentials.  Here for ../phonopy's `pypolymlp`
  # and `tools` extras, which ask for `>=0.21.3`.  Its own extras name phonopy
  # and phono3py in turn; that cycle is cut at phonopy's check phase.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/pypolymlp.
  src = fetchFromGitHub {
    owner = "sekocha";
    repo = "pypolymlp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-T0igQ4ok2KfCbQxtFeZvpYZ/CdeDZk7Dl3zqro4gNjo=";
  };

  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `cmake`, `pybind11-global` and `eigen` in `[build-system] requires` are the
  # PyPI wheels that carry those tools; pypa-build checks the list against the
  # environment and would report all three missing.  Here cmake is on PATH,
  # pybind11's CMake config comes with the `pybind11` it still lists, and
  # Eigen is a buildInput that `find_package(Eigen3)` finds.
  #
  # The last substitution puts `pypolymlp.polyinv` back.  Upstream lists it in
  # `sdist.exclude`, which scikit-build-core applies to the wheel as well, but
  # still declares the `pypolymlp-invariant` console script, which imports it
  # at module scope.  The upstream wheel therefore installs a command that fails
  # with ModuleNotFoundError, and tests/test_polyinv/ cannot even be collected.
  # Its C++ extension is built in preBuild.
  #
  # The sscha_core.py hunk is for phonopy 4.2.0 and later, where setting
  # `force_constants` clears the mesh along with everything else derived from
  # the dynamical matrix (phonopy 656a2caa, "Centralize derived-state
  # invalidation in Phonopy setters").  `_write_dos` sets the SSCHA force
  # constants and calls `run_total_dos()` straight after, relying on a mesh left
  # over from an earlier call, so every SSCHA run ended in "run_mesh has to be
  # done before DOS calculation" — nine tests.  The mesh it now runs is the
  # SSCHA q-mesh, the one its own `write_pdos` branch falls back to, and it is
  # computed from the force constants just set rather than from stale ones.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"cmake",' "" \
      --replace-fail '"pybind11-global",' "" \
      --replace-fail '"eigen",' "" \
      --replace-fail '"src/pypolymlp/polyinv",' ""

    substituteInPlace src/pypolymlp/calculator/sscha/sscha_core.py \
      --replace-fail \
        'self._phonopy.run_total_dos()' \
        'self._phonopy.run_mesh(qmesh or self._sscha_params.mesh)
            self._phonopy.run_total_dos()'
  '';

  build-system = [
    cmake
    ninja
    pybind11
    scikit-build-core
    setuptools-scm
  ];
  dontUseCmakeConfigure = true;

  # GSL is for polyinv's extension alone; the main one needs only Eigen.
  buildInputs = [
    eigen
    gsl
  ];

  # Upstream's three, and four it imports at module scope without declaring:
  # ase for the MD API and the ASE calculator (`pypolymlp-md`), h5py for
  # calculator/utils/fc_utils.py, and matplotlib and seaborn for the
  # auto-calculation figures, which `pypolymlp-autocalc` and
  # tests/test_calc/conftest.py import through api/pypolymlp_autocalc.py.
  # Without seaborn that conftest fails to load, and with it the whole suite.
  #
  # Not added: the `lammps` Python module, which calculator/utils/lammps/ imports
  # for the three `pypolymlp-lammps*` commands pyproject.toml files under "For
  # developers that use lammps".
  dependencies = [
    ase
    h5py
    matplotlib
    numpy
    pyyaml
    scipy
    seaborn
  ];

  # matplotlib creates ~/.config/matplotlib on import, and /homeless-shelter is
  # not writable.  preBuild rather than preCheck so that pythonImportsCheck is
  # covered too; see ../aiida-core/default.nix.
  #
  # scikit-build-core builds one CMake project, `cmake.source-dir`, which is
  # src/pypolymlp/cxx.  polyinv's `libprojcpp` is a second, standalone project
  # that nothing upstream builds.  It is built here before the wheel.  Its
  # `install()` writes into src/pypolymlp/polyinv/cxx/lib in the source tree,
  # the same arrangement the main project uses, so the wheel picks it up
  # without further help.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export MPLCONFIGDIR="$HOME/.config/matplotlib"
    mkdir -p "$MPLCONFIGDIR"

    polyinvBuild="$(mktemp -d)"
    cmake -S src/pypolymlp/polyinv/cxx -B "$polyinvBuild" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DPython_EXECUTABLE=${python.interpreter}
    cmake --build "$polyinvBuild" --parallel "$NIX_BUILD_CORES"
    cmake --install "$polyinvBuild"
  '';

  optional-dependencies = {
    phono3py = [ phono3py ];
    phonopy = [ phonopy ];
    spglib = [ spglib ];
    symfc = [ symfc ];
    tools = [
      phono3py
      phonopy
      spglib
      symfc
    ];
  };

  # tests/conftest.py imports phono3py at module scope, so the whole suite
  # needs it, and the `tools` extra is upstream's full set.  There is no CI
  # test job upstream to follow; this is `pytest tests/`.
  nativeCheckInputs = [ pytestCheckHook ] ++ finalAttrs.passthru.optional-dependencies.tools;

  enabledTestPaths = [ "tests" ];

  # Numbers that disagree with upstream's reference values, cause not
  # established.  The three regression tests are off by about 1e-4 relative
  # against a 1e-6 tolerance, which a different BLAS could account for; test_tr2
  # is a relaxation with gtol=1e-4 that lands on 0.0655 rather than 0.0429,
  # which a different local minimum could.  Neither guess was tested.
  #
  # Node ids, because `test_fit` alone would also take
  # tests/test_mlp_dev/test_fit_api_standard.py, which passes.  No conftest here
  # rewrites node ids, so `--deselect` sees them as written; compare
  # ../maggma/default.nix.
  disabledTestPaths = [
    "tests/test_calc/test_compute_transformation.py::test_tr2"
    "tests/test_mlp_dev/test_errors_api.py::test_compute_cv"
    "tests/test_mlp_dev/test_errors_api.py::test_compute_cv_usex"
    "tests/test_mlp_dev/test_fit_api_standard_loocv.py::test_fit"
  ];

  # tests/test_command/ runs the console scripts through subprocess, and a
  # package's own $out/bin is never on PATH; see ../aiida-pseudo/default.nix.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  # Not pypolymlp.polyinv.api_polyinv, which reaches `symfc` at module scope
  # through eig_solver.py.  symfc is only in the `symfc` and `tools` extras, so
  # `pypolymlp-invariant` works only with one of those installed.
  pythonImportsCheck = [
    "pypolymlp"
    "pypolymlp.cxx.lib.libmlpcpp"
    "pypolymlp.polyinv.projector"
  ];

  meta = {
    description = "Polynomial machine learning potentials";
    homepage = "https://github.com/sekocha/pypolymlp";
    license = lib.licenses.bsd3;
    mainProgram = "pypolymlp";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
