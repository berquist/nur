{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  ase,
  matscipy,
  numpy,
  pandas,
  pyyaml,
  questionary,
  requests,
  rich,
  scikit-learn,
  scipy,
  sympy,
  tensorflow,
  tf-keras,
  tqdm,
}:

# tensorpotential — Graph Atomic Cluster Expansion (GRACE), from ICAMS.  The
# distribution is `tensorpotential`; the repository is `grace-tensorpotential`,
# and matcalc's `grace` extra asks for the former.
#
# **This is the one unfree package in this repository.**  Its licence is the
# Academic Software Licence, which is GPLv2 with a non-commercial restriction
# substituted for clause 9 — its own preamble says "ASL is not an open-source
# licence".  See `meta.license` below for what that costs: `ci.nix` filters it
# out of both the build set and the cachix push, which is the reason that filter
# was kept after molcat was removed rather than deleted as dead code.
buildPythonPackage (finalAttrs: {
  pname = "tensorpotential";
  version = "0.6.1";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ICAMS";
    repo = "grace-tensorpotential";
    tag = finalAttrs.version;
    hash = "sha256-etSSoXP+UgDMNN0dLUEdMZdJDhlQZzFgJs4ZfxEqMiA=";
  };

  # Upstream asks for `tensorflow[and-cuda]` on Linux, an extra that exists only
  # on the PyPI wheel: it pulls the NVIDIA CUDA runtime in as a pile of
  # `nvidia-*` wheels.  nixpkgs' tensorflow has no such extra, and
  # `pythonRuntimeDepsCheckHook` fails the wheel over an extra it cannot
  # resolve — this is not a version bound, so `pythonRelaxDeps` cannot reach it.
  #
  # Dropping the extra and the bound leaves `tensorflow; sys_platform ==
  # 'linux'`, which is a requirement nixpkgs can satisfy.  CUDA is not lost by
  # this: whether TensorFlow has GPU support is decided by nixpkgs' `tensorflow`,
  # not by a requirement string.  The neighbouring win32/darwin line is left
  # alone, its marker being false here anyway.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'tensorflow[and-cuda]<=2.20' 'tensorflow'
  '';

  build-system = [ setuptools ];

  dependencies = [
    ase
    matscipy
    numpy
    pandas
    pyyaml
    questionary
    requests
    rich
    scikit-learn
    scipy
    sympy
    tensorflow
    tf-keras
    tqdm
  ];

  # Keras writes `~/.keras/keras.json` the first time it is imported, and the
  # default `/homeless-shelter` is not writable — so even `pythonImportsCheck`
  # needs somewhere to put it.  Same one-line fix as ../matgl and ../maml.
  preBuild = ''
    export HOME="$(mktemp -d)"
  '';

  # The suite is not run.  Its session-scope conftest fixture builds a
  # GRACE-2L model and fits it under TensorFlow before any test executes, and
  # six modules — `test_foundation_model_regression`, `test_fm_shift_auto`,
  # `test_wizard` and the rest — pull pretrained foundation-model weights over
  # the network through `grace_models`.  Neither is something a build sandbox
  # can offer, and what is left after removing both is not worth the TensorFlow
  # rebuild it would cost.
  #
  # `pythonImportsCheck` is the real check here: it exercises TensorFlow, the
  # legacy-Keras shim and the ASE calculator, which is the whole surface
  # matcalc's `grace` backend touches.  `tensorpotential/__init__.py` sets
  # `TF_USE_LEGACY_KERAS=1` itself, so nothing needs a wrapper for it.
  doCheck = false;

  pythonImportsCheck = [
    "tensorpotential"
    "tensorpotential.calculator"
    "tensorpotential.calculator.asecalculator"
    "tensorpotential.potentials"
    "tensorpotential.tensorpot"
  ];

  meta = {
    description = "Graph Atomic Cluster Expansion (GRACE) interatomic potentials";
    homepage = "https://github.com/ICAMS/grace-tensorpotential";
    # No SPDX identifier exists for this one, so it is spelled out.  The terms
    # are GPLv2's with clause 9 removed and a clause 13 added restricting use to
    # non-commercial purposes, which is what makes it unfree.
    #
    # `redistributable` is spelled out rather than left off.  A raw attrset gets
    # no defaulting — `lib.licenses`' own entries take `redistributable ? free`
    # from `mkLicense`, and this is not one of them — so omitting it leaves the
    # field simply absent.  False is the answer that matters: ASL does permit
    # redistribution, but only onward to non-commercial users, and a public
    # binary cache cannot make that distinction about whoever fetches from it.
    license = {
      fullName = "Academic Software Licence";
      shortName = "asl";
      url = "https://github.com/ICAMS/grace-tensorpotential/blob/${finalAttrs.version}/LICENSE.md";
      free = false;
      redistributable = false;
    };
    mainProgram = "gracemaker";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
