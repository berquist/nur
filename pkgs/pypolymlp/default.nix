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
  seaborn,
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
  #
  # `pypolymlp-invariant` is deleted for the reason `disabledTestPaths` below
  # gives: it runs `pypolymlp.polyinv`, which upstream does not ship, so the
  # installed script could only fail with ModuleNotFoundError.
  # test_command_lines_developer runs it with `--help`, so its two lines go
  # too, and the test keeps its other three scripts.  The tests have CRLF
  # line endings, so that two-line pattern is a `$'…'` string with `\r\n`.
  #
  # phonopy 4.10 clears every derived result, the mesh included, when force
  # constants are set (`_invalidate_derived("dm_inputs")`).  pypolymlp 0.22.2
  # sets the final SSCHA force constants and then calls `run_total_dos`, which
  # relied on the mesh from the previous step still being there.  Eleven
  # SSCHA tests failed with "run_mesh has to be done before DOS calculation".
  # The fix computes the mesh on the `qmesh` that `calc_save_dos` is already
  # given, with the same call `HarmonicReciprocal.run` uses.  So the DOS now
  # comes from the force constants it is saved next to.  Before, the mesh
  # came from the force constants of the step before.
  #
  # Two reference values are stale at v0.22.2, and upstream has since
  # changed both, after the tag, to the values computed here:
  # `test_gsfe1`'s 0.636360235 and `test_tr2`'s 0.04286155857041152.  Both
  # are the same on every OpenBLAS kernel, unlike the four below.
  #
  # The other four depend on the OpenBLAS kernel.  The same inputs under
  # `OPENBLAS_CORETYPE` default, Haswell, Sandybridge and Prescott give
  # different results:
  #
  # - test_sscha_core and test_symfc_utils check `fc2[0, 0, 0, 0]` from force
  #   constants built with every symfc basis coefficient set to one.  The
  #   basis vectors are eigenvectors, so each one's sign is arbitrary, and the
  #   value came out as -1.16, -1.37 and 0.76 against an expected 1.45.  No
  #   tolerance can fix that, so those assertions are removed, together with
  #   the average frequency that follows from the same force constants.  The
  #   shape, harmonic-start and sign-free projection assertions stay.
  # - test_compute_cv and test_compute_cv_usex check four LOOCV errors each.
  #   Across the four kernels, the energy RMSE and MAE are up to 1.0% from the
  #   reference, so `rel=2e-2`, and the force RMSE and MAE up to 0.26%, so
  #   `rel=5e-3`.  test_fit's LOOCV `rmse_test` moves by up to 0.2%, so
  #   `rel=5e-3` too.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '    "cmake",' "" \
      --replace-fail '    "pybind11-global",' "" \
      --replace-fail '    "eigen",' "" \
      --replace-fail \
        'pypolymlp-invariant = "pypolymlp.api.developer.run_polymlp_polyinv:run"' ""
    substituteInPlace tests/test_command/test_command.py \
      --replace-fail \
        $'    cmd = "pypolymlp-invariant --help"\r\n    subprocess.run(cmd.split(), check=True)\r\n' ""

    substituteInPlace src/pypolymlp/calculator/sscha/harmonic_reciprocal_base.py \
      --replace-fail \
        '        self._ph.run_total_dos()' \
        '        self._ph.run_mesh(qmesh)
            self._ph.run_total_dos()'

    substituteInPlace tests/test_calc/test_api_gsfe.py \
      --replace-fail 'pytest.approx(0.636360235)' 'pytest.approx(0.6363613826047292)'
    substituteInPlace tests/test_calc/test_compute_transformation.py \
      --replace-fail 'pytest.approx(0.04286155857041152)' 'pytest.approx(0.06553755973360609)'

    substituteInPlace tests/test_calc/test_sscha_core.py \
      --replace-fail \
        '    assert sscha.force_constants[0, 0, 0, 0] == pytest.approx(1.4529650641782414)' "" \
      --replace-fail \
        '    assert np.average(freq) == pytest.approx(1.613959681934481)' ""
    substituteInPlace tests/test_calc/test_sscha_symfc_utils.py \
      --replace-fail \
        '    assert fc2[0, 0, 0, 0] == pytest.approx(-0.004642281307253422)' ""
    substituteInPlace tests/test_mlp_dev/test_errors_api.py \
      --replace-fail '1.7805415513515136e-06)' '1.7805415513515136e-06, rel=2e-2)' \
      --replace-fail '0.0008358087025103993)' '0.0008358087025103993, rel=5e-3)' \
      --replace-fail '1.3905925966991775e-06)' '1.3905925966991775e-06, rel=2e-2)' \
      --replace-fail '0.0006663275130366884)' '0.0006663275130366884, rel=5e-3)' \
      --replace-fail '1.77760560018981e-06)' '1.77760560018981e-06, rel=2e-2)' \
      --replace-fail '0.0008362595489770875)' '0.0008362595489770875, rel=5e-3)' \
      --replace-fail '1.3890524524384773e-06)' '1.3890524524384773e-06, rel=2e-2)' \
      --replace-fail '0.0006666482589386611)' '0.0006666482589386611, rel=5e-3)'
    substituteInPlace tests/test_mlp_dev/test_fit_api_standard_loocv.py \
      --replace-fail \
        'pytest.approx(0.0008210162371496754)' \
        'pytest.approx(0.0008210162371496754, rel=5e-3)'
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

  # `ase`, `joblib`, `matplotlib` and `seaborn` are imported by the package and
  # its tests without being declared anywhere; they are check inputs because
  # the suite is where they were found, not because they are test-only.  The
  # README lists seaborn, and three plotting modules under
  # `pypolymlp.calculator` import it at module scope.  tests/test_calc/
  # conftest.py reaches one of them through `PypolymlpAutoCalc`, so without it
  # the whole of tests/test_calc fails to collect.
  nativeCheckInputs = [
    pytestCheckHook
    ase
    joblib
    matplotlib
    seaborn
  ]
  ++ finalAttrs.passthru.optional-dependencies.tools;

  # The source tree has a `pypolymlp/` too, without the compiled `cxx/lib` that
  # CMake installs into the wheel, so it would shadow the installed copy.
  # tests/test_command runs the console scripts by name, so they need to be on
  # PATH.
  preCheck = ''
    rm -r src
    export PATH="$out/bin:$PATH"
  '';

  # Upstream marks its slowest tests `big` and skips them unless `--runbig` is
  # passed; left at that default.
  enabledTestPaths = [ "tests" ];

  # tests/test_polyinv imports `pypolymlp.polyinv`, which upstream leaves out
  # of its distributions on purpose: `sdist.exclude` in pyproject.toml names
  # `src/pypolymlp/polyinv`, and its C++ extension (`libprojcpp`) has its own
  # CMakeLists that the build never runs.  So the tests have nothing to import.
  disabledTestPaths = [ "tests/test_polyinv" ];

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
