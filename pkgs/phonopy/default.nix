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

  # optional-dependencies
  # In the aiida overlay, not this one, so null when overlays.materials is
  # composed without it — see the `phonopy` binding in
  # ../../overlays/default.nix.  The extra is then simply absent.
  cp2k-input-tools ? null,
  pypolymlp,
  seekpath,

  # tests
  pytestCheckHook,
  alm,
  ase,
}:

# phonopy — harmonic and quasi-harmonic phonons, and the base that ../phono3py
# is built on.
#
# A guarded backport, and the reason ../phonors and ../symfc are here.
# ../phono3py follows phonopy's minor version exactly — every release pins
# `phonopy>=X.Y,<X.(Y+1)`, and does so because it calls phonopy API that the
# previous minor lacks (4.7 added `get_tetrahedra_relative_gr_grid_address`,
# which phono3py 4.7 uses straight away).  So the two have to move together,
# and the channels here carry three different phonopys: 4.4.0 in the locked
# nixpkgs, 4.7.2 on the newest unstable, 3.5.1 on nixos-26.05.  One phonopy for
# every channel is what lets one phono3py build on all of them.
#
# The `phonopy` binding in ../../overlays/default.nix takes the channel's own
# copy once it reaches 4.10, so this never *downgrades* a channel.
buildPythonPackage (finalAttrs: {
  pname = "phonopy";
  version = "4.10.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phonopy";
    tag = "v${finalAttrs.version}";
    hash = "sha256-xjLg7GlenCT0Blym+ylgC7Ay/oy3AVvWiBlaPm8dprY=";
  };

  # scikit-build-core takes the version from setuptools-scm
  # (`metadata.version.provider`), which needs a git checkout.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = finalAttrs.version;

  # `nanobind<2.10.0` in the build requirements, against nixpkgs' 2.13 — the
  # same pin, and the same fix, as ../phono3py and nixpkgs' own phonopy.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"nanobind<2.10.0"' '"nanobind"'
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

  # Upstream's extras, `tools` being `seekpath` plus `pypolymlp`.  `dev` is
  # pytest, ruff and mypy, and is left out.
  #
  # `pypolymlp` here is the real one, with its suite: an extra is not a build
  # input, so it does not close the cycle described at `nativeCheckInputs`.
  optional-dependencies =
    let
      extras = {
        seekpath = [ seekpath ];
        pypolymlp = [ pypolymlp ];
      }
      // lib.optionalAttrs (cp2k-input-tools != null) {
        cp2k = [ cp2k-input-tools ];
      };
    in
    extras
    // {
      tools = extras.seekpath ++ extras.pypolymlp;
    };

  # Every extra, and `ase` for the one test that `importorskip`s it.
  #
  # pypolymlp with `doCheck = false`, and that is a cycle being cut rather than
  # coverage being given up: ../pypolymlp's suite imports phono3py, which
  # depends on this package, so a checked pypolymlp here would be a dependency
  # loop at the derivation level.  The unchecked one still installs the same
  # module, which is all the pypolymlp tests here need.  ../pypolymlp has the
  # other half of this note.
  #
  # `alm` is not an extra at all — upstream declares it nowhere — but phonopy
  # offers it as a force-constant calculator and six tests `importorskip` it.
  # ../alm is packaged for that alone.
  nativeCheckInputs = [
    pytestCheckHook
    alm
    ase
    seekpath
    (pypolymlp.overridePythonAttrs { doCheck = false; })
  ]
  ++ lib.optional (cp2k-input-tools != null) cp2k-input-tools;

  # nixpkgs sets this on Darwin only, against an abort in the check phase.  Set
  # everywhere here: a build has no display on any platform, and the plotting
  # tests only need a backend that renders to a buffer.
  env.MPLBACKEND = "Agg";

  # The unpacked `phonopy/` has no compiled `_phonopy` / `_recgrid`, and from
  # the source root it would shadow the installed package — the same trap as
  # ../sella and ../wignernj.
  preCheck = ''
    rm -r phonopy
  '';

  enabledTestPaths = [ "test" ];

  pythonImportsCheck = [
    "phonopy"
    "phonopy._phonopy"
    "phonopy._recgrid"
  ];

  # The other half of ../phono3py's policy: a bump here that crosses a minor
  # breaks phono3py until it follows, so the two are bumped together by hand.
  passthru.updatePolicy = {
    mode = "report";
    reason = "../phono3py pins this minor version; bump together with it";
  };

  meta = {
    description = "Phonon calculations at the harmonic and quasi-harmonic levels";
    homepage = "https://phonopy.github.io/phonopy/";
    changelog = "https://phonopy.github.io/phonopy/changelog.html";
    license = lib.licenses.bsd3;
    mainProgram = "phonopy";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
