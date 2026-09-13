{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  gfortran,
  pkg-config,
  toml-f,

  # build-system
  meson,
  ninja,
  setuptools,

  # dependencies
  numpy,

  # optional-dependencies
  ase,

  # tests
  pytestCheckHook,
}:

# lwoniom — the bookkeeping half of a multi-centre ONIOM calculation: which
# atoms belong to which layer, where the link atoms go, and how the layers'
# energies, gradients and Hessians combine.  It computes no energies itself;
# it is what a driver such as crest wraps around calculators that do.
#
# A Fortran library with a C API and a Python binding, from the crest group.
# Nothing in this repository depends on it yet — it is packaged because it is
# small, self-contained and adjacent to the chemtools family.  Internal, not
# re-exported.
#
# **This packages the binding, which builds the library on its way through.**
# Upstream supports exactly that — `pip install .` runs meson and bundles
# `liblwoniom.so` into the installed package — so there is no separate
# `pkgs.lwoniom` C library here, unlike the ../chemfiles and ../chemfiles-python
# split.  The reason that split exists is that both audiences want the C++
# library on its own terms; here the only consumer of the Fortran library that
# matters is crest, which vendors lwoniom as a meson subproject rather than
# linking an installed one.
buildPythonPackage (finalAttrs: {
  pname = "lwoniom";
  version = "0.0.2";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "crest-lab";
    repo = "lwoniom";
    tag = "v${finalAttrs.version}";
    hash = "sha256-33cKyUYnG3KJ54oAh2zOv6frRN/i2XKeVDpEdISlncE=";
  };

  # meson and ninja from the *Python* package set rather than the top level, and
  # the difference matters twice over.  `setup.py` shells out as
  # `sys.executable -m mesonbuild.mesonmain` and falls back to
  # `sys.executable -m ninja`, so what it needs is the modules importable by the
  # interpreter building the wheel — not the programs on PATH.  And the
  # top-level packages carry setup hooks that would seize the configure, build
  # and install phases for a project whose real build is driven from
  # `build_py`.  They are different derivations; `python313Packages.meson` is
  # the module, `pkgs.meson` is the wrapped program.
  build-system = [
    meson
    ninja
    setuptools
  ];

  # gfortran because the library is Fortran, and pkg-config plus toml-f because
  # of what `meson_options.txt` calls the option: `feature 'auto'`.  Auto means
  # meson takes toml-f if it can find one and silently proceeds without it
  # otherwise — but the `fallback` beside it names the `subprojects/toml-f`
  # submodule, which a `fetchFromGitHub` without `fetchSubmodules` does not
  # have and a build sandbox cannot clone.  Supplying nixpkgs' toml-f (0.5.1,
  # against upstream's `>=0.2.4`) is what keeps the TOML input parser in the
  # library rather than having it quietly compiled out.
  nativeBuildInputs = [
    gfortran
    pkg-config
  ];

  buildInputs = [ toml-f ];

  dependencies = [ numpy ];

  optional-dependencies = {
    ase = [ ase ];
  };

  # The whole of upstream's `test` extra.  Both modules are ASE-facing: one
  # drives the `lwoniom.ase_calc.ONIOM` calculator against EMT and
  # Lennard-Jones, the other builds layer assignments directly.
  nativeCheckInputs = [
    pytestCheckHook
    ase
  ];

  # `[tool.setuptools.package-dir]` puts the package at `python/lwoniom`, so
  # `import lwoniom` from the source root finds the *installed* copy — the one
  # with `liblwoniom.so` bundled beside it — rather than the source tree.  That
  # is the shadowing trap ../sella and ../vesin both hit, avoided here by
  # upstream's own layout rather than by deleting anything.
  enabledTestPaths = [ "python/tests" ];

  pythonImportsCheck = [
    "lwoniom"
    "lwoniom.core"
    "lwoniom.library"
  ];

  meta = {
    description = "Light-weight multi-centre ONIOM bookkeeping library";
    homepage = "https://github.com/crest-lab/lwoniom";
    license = lib.licenses.lgpl3Plus;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
