{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cmake,
  nanobind,
  ninja,
  numpy,
  scikit-build-core,
  setuptools-scm,

  # dependencies
  h5py,
  matplotlib,
  phonors,
  pyyaml,
  scipy,
  spglib,
  symfc,

  # optional-dependencies.  cp2k-input-tools lives in the aiida overlay, and
  # the materials overlay has to work without it, so the `cp2k` extra is empty
  # when that overlay is not composed.
  cp2k-input-tools ? null,
  pypolymlp,
  seekpath,

  # tests
  pytestCheckHook,
}:

let
  # pypolymlp's own suite imports phono3py, which depends on this, so the copy
  # this check phase uses has to have its check phase off.  Only the check is
  # cut: the package is the same.  ../dpdata-plugin-test cuts its cycle the same
  # way.
  pypolymlpForTests = pypolymlp.overridePythonAttrs { doCheck = false; };
in
buildPythonPackage (finalAttrs: {
  pname = "phonopy";
  version = "4.6.0-unstable-2026-09-26";
  pyproject = true;
  __structuredAttrs = true;

  # **A snapshot of `main`, replacing nixpkgs' phonopy in the materials
  # overlay**, which is what ../phono3py at its own `main` needs.  phono3py pins
  # `phonopy>=4.6.0,<4.7.0` and then imports
  # `phonopy.phonon.tetrahedron_method.get_tetrahedra_relative_gr_grid_address`,
  # which phonopy added in 75987162 the day after tagging v4.6.0.  No release
  # has it yet, so the floor phono3py declares is looser than the one it has.
  #
  # The guard in ../../overlays/default.nix hands back nixpkgs' own derivation
  # at the first release past 4.6.0.  Every one of those contains 75987162,
  # since it is on `main`.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/phonopy.
  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phonopy";
    rev = "57bccd6484d925e720ce5805e69d337d34d313a2";
    hash = "sha256-z7Jp8KWKg2jsZxeKzPBKnWF9hkTnApZ0F6WZfcKTkP0=";
  };

  # scikit-build-core takes the version from setuptools-scm, which needs a
  # repository.  The part before the dash, so that phono3py's `>=4.6.0,<4.7.0`
  # holds: `4.6.1.dev37`, which is what the snapshot is, would be a pre-release
  # and PEP 440 leaves those out of a range that does not name one.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" finalAttrs.version);

  # nixpkgs' own derivation carries the same rewrite: `nanobind<2.10.0` against
  # 2.13, and a build-system pin, which pythonRelaxDeps cannot reach.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "nanobind<2.10.0" "nanobind"
  '';

  build-system = [
    cmake
    nanobind
    ninja
    numpy
    scikit-build-core
    setuptools-scm
  ];
  dontUseCmakeConfigure = true;

  # `main` asks for `phonors>=0.4.0`, and needs 0.5.0: it calls
  # `phonors.grid_indices_from_addresses`, which 0.5.0 introduced.  The
  # materials overlay supplies 0.5.0; see ../phonors.
  dependencies = [
    h5py
    matplotlib
    numpy
    phonors
    pyyaml
    scipy
    spglib
    symfc
  ];

  optional-dependencies = {
    cp2k = lib.optional (cp2k-input-tools != null) cp2k-input-tools;
    seekpath = [ seekpath ];
    pypolymlp = [ pypolymlp ];
    tools = [
      pypolymlp
      seekpath
    ];
  };

  # Nine test modules use pypolymlp, among them test/interface/test_pypolymlp.py
  # and the sscha suite, so every extra is a check input, pypolymlp as the copy
  # with its own check off.
  nativeCheckInputs = [
    pytestCheckHook
    pypolymlpForTests
    seekpath
  ]
  ++ finalAttrs.passthru.optional-dependencies.cp2k;

  # matplotlib creates ~/.config/matplotlib on import, and /homeless-shelter is
  # not writable.  preBuild rather than preCheck so that pythonImportsCheck is
  # covered too; see ../aiida-core/default.nix.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export MPLCONFIGDIR="$HOME/.config/matplotlib"
    mkdir -p "$MPLCONFIGDIR"
  '';

  # As in nixpkgs: the source tree's phonopy/ would shadow the installed one,
  # which has the compiled extension.
  preCheck = ''
    rm -r phonopy
  '';

  pythonImportsCheck = [
    "phonopy"
    "phonopy.phonon.tetrahedron_method"
  ];

  meta = {
    description = "Phonon calculations at harmonic and quasi-harmonic levels";
    homepage = "https://phonopy.github.io/phonopy/";
    changelog = "https://phonopy.github.io/phonopy/changelog.html";
    license = lib.licenses.bsd3;
    mainProgram = "phonopy";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
