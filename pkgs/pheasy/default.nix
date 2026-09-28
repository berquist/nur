{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,

  # dependencies
  ase,
  f90nml,
  h5py,
  numba,
  numpy,
  scikit-learn,
  scipy,
  spglib,

  # optional-dependencies
  libtetrabz,
  opt-einsum,
}:

buildPythonPackage rec {
  pname = "pheasy";
  version = "0.1.0-unstable-2026-03-26";
  pyproject = true;

  # High-order force constants by compressive sensing, and what ../atomate2's
  # pheasy flow shells out to, as a sequence of `pheasy ...` commands.
  #
  # **A fork, on a branch that is not its default.**  atomate2 names
  # `hpsahasrabuddhe/pheasy@support-disp-force-matrix-input`, two commits on
  # top of that fork's `develop`: 08ab5cc adds `--disp_matrix_file` and
  # `--force_matrix_file`, which atomate2 passes, and e67a777 relaxes an
  # `ase==3.22.1` pin.  Upstream's `develop`, at gitlab.com/cplin/pheasy, has
  # neither flag, so although it is newer it is not a substitute.  See
  # `passthru.updatePolicy` for what that means to the updater.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/pheasy.
  src = fetchFromGitLab {
    owner = "hpsahasrabuddhe";
    repo = "pheasy";
    rev = "e67a777ecfde5ab368d71167837b099df75cfd4c";
    hash = "sha256-L4uqYaRSYPwvzlr+DbpUJj3+xVHhAPw+5bL3AELYMQU=";
  };

  # setup.py, not the `[tool.poetry]` table beside it: the build backend is
  # setuptools, so Poetry's `python = ">=3.8.1,<3.12"` is never read, and what
  # is enforced is `python_requires=">=3.8.1"` and requirements/requirements.txt.
  # cxx/ and fortran/ are not built by it; nothing in pheasy/ imports them.
  build-system = [ setuptools ];

  # requirements/requirements.txt, exactly.
  dependencies = [
    ase
    f90nml
    h5py
    numba
    numpy
    scikit-learn
    scipy
    spglib
  ];

  # requirements/requirements-extras.txt.  Both are imported lazily, behind a
  # message naming the package.  libtetrabz is pinned `==0.1.1` there, which
  # nothing enforces for an extra, and which cannot work here anyway: 0.1.1
  # still uses `numpy.float_`, gone since numpy 2.  See ../libtetrabz.
  optional-dependencies = {
    extras = [
      libtetrabz
      opt-einsum
    ];
  };

  # Four functions are `@njit(cache=True)`, and numba decides where its cache
  # goes when the decorator runs: beside the module if that is writable, under
  # the user's cache directory if not.  In the store the first is read-only and
  # /homeless-shelter makes the second fail too.  preBuild rather than preCheck
  # so pythonImportsCheck is covered; see ../aiida-core/default.nix.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # There is no suite: tests/ holds structures and force-constant data and no
  # test modules.  What can be checked is that the command atomate2 runs parses
  # its arguments, which imports the whole CLI.
  checkPhase = ''
    runHook preCheck
    $out/bin/pheasy --help > /dev/null
    runHook postCheck
  '';

  pythonImportsCheck = [
    "pheasy"
    "pheasy.main"
    "pheasy.core.constructors"
  ];

  # Read by ../../scripts/update-universe.nix.  Branch mode follows a
  # repository's *default* branch, which on this fork is `develop` — the one
  # without 08ab5cc.  This names the branch atomate2 does.
  passthru.updatePolicy.branch = "support-disp-force-matrix-input";

  meta = {
    description = "Calculator for high-order force constants and phonon quasiparticles";
    homepage = "https://gitlab.com/cplin/pheasy";
    license = lib.licenses.gpl3Only;
    mainProgram = "pheasy";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
