{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cython,
  numpy,
  setuptools,
  wheel,

  # dependencies
  matplotlib,
  pillow,
  pyopengl,
  pyrr,
  pyside6,
  scipy,

  # tests
  libGL,

  # The Mesa drivers, threaded in from the top level at the callPackage site in
  # ../../overlays/default.nix rather than taken from the ambient scope.  A
  # python-set callPackage resolves the Python attribute first, and nixpkgs has
  # a `python3Packages.mesa` — a removal stub that throws:
  #
  #   error: python3Packages.mesa has been removed because it has been marked
  #   as broken since at least November 2024.
  #
  # So a plain `mesa` argument does not merely pick the wrong thing, it takes
  # the whole evaluation down.  Same treatment as chemfiles-python's
  # `chemfilesLib`.
  mesaDrivers,

  pytest-cov,
  pytest-qt,
  pytest-xvfb,
  pytestCheckHook,
  xorg-server,
}:

buildPythonPackage rec {
  pname = "molara";
  # The distribution is `Molara`; the import name is `molara`.  0.1.2 is what
  # src/molara/__init__.py declares and what pyproject.toml reads back through
  # `version = {attr = "molara.__version__"}` — here the tag and the source
  # agree, unlike ../fireworks, they are just 98 commits apart.
  version = "0.1.2-unstable-2026-08-17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Molara-Lab";
    repo = "Molara";
    rev = "8ffc8580ac142c5834818be8aada3f5f4c5c7aa9";
    hash = "sha256-Qg2zekyyePXHYbJogbsELLNVo4d9h52dwYvZQgA5Nhk=";
  };

  build-system = [
    cython
    numpy
    setuptools
    wheel
  ];

  # `PySide6>=6.3.0,<=6.10.1` against nixpkgs' 6.11.1.  An upper bound rather
  # than a known incompatibility — upstream pins the newest they have tested —
  # and pythonRelaxDeps is the right tool here, unlike ../sella, because this is
  # a *runtime* dependency in [project.dependencies] rather than an entry in
  # [build-system] requires.  That table is checked before the backend loads and
  # the hook never touches it.
  pythonRelaxDeps = [ "PySide6" ];

  dependencies = [
    matplotlib
    numpy
    pillow
    pyopengl
    pyrr
    pyside6
    scipy
  ];

  nativeCheckInputs = [
    pytest-cov
    pytest-qt
    pytest-xvfb
    pytestCheckHook

    # The X server itself.  pytest-xvfb is only the *plugin*: it drives
    # pyvirtualdisplay, which execs a program called `Xvfb` off PATH, and when
    # that program is missing it warns and does nothing rather than failing.
    # So without this the suite runs with no DISPLAY at all.
    xorg-server
  ];

  # pytest.ini sets `qt_api=pyside6`, so pytest-qt is not optional here; it is
  # what makes the setting mean anything.
  #
  # `pytest-split` is in upstream's `tests` extra and is deliberately absent:
  # nixpkgs does not carry it, and it only shards a suite across CI workers.
  # It is not referenced from any test module, only from upstream's workflow
  # files, so there is nothing to patch out.
  #
  # The rest of this is what it takes to compile a shader with no graphics
  # hardware.  tests/molara/rendering/test_shaders.py builds a QApplication, a
  # QOpenGLWidget and a 3.3 core profile, then compiles every .glsl file in the
  # package; tests/molara/gui/test_main_window.py does the same through the real
  # window.  With no display and no GL driver that does not fail, it *aborts* —
  # SIGABRT out of Qt, with no Python traceback and no Qt diagnostic:
  #
  #   tests/molara/rendering/test_shaders.py Fatal Python error: Aborted
  #     File ".../test_shaders.py", line 36 in test_compile_shaders
  #
  # which is line `QApplication([])`.  Worth knowing that the eight camera tests
  # before it pass: test_camera.py is pure arithmetic and never touches Qt, so
  # the shader module is the first thing in the suite to want a display, and the
  # abort looks like a shader problem when it is not one yet.
  #
  # mesa supplies the llvmpipe software rasteriser, LIBGL_DRIVERS_PATH points
  # the loader at it, and LIBGL_ALWAYS_SOFTWARE stops it looking for hardware.
  # llvmpipe advertises GL 4.5, so the 3.3 core profile the test asks for is
  # comfortably within range.
  preCheck = ''
    export HOME="$(mktemp -d)"
    export MPLBACKEND=Agg
    export LIBGL_DRIVERS_PATH="${lib.getLib mesaDrivers}/lib/dri"
    export LIBGL_ALWAYS_SOFTWARE=1
    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [
        libGL
        mesaDrivers
      ]
    }''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
  '';

  pythonImportsCheck = [
    "molara"
    # The Cython extension, imported explicitly: a build where cythonize
    # produced nothing still imports the pure-Python top level perfectly.  Same
    # guard ../sella uses.
    "molara.tools.raycasting"
  ];

  meta = {
    description = "Visualisation tool for chemical structures";
    homepage = "https://github.com/Molara-Lab/Molara";
    license = lib.licenses.gpl3Only;
    mainProgram = "molara";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
