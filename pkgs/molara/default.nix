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
  libglvnd,
  pytest-cov,
  pytest-qt,
  pytest-xvfb,
  pytestCheckHook,
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
  ];

  # pytest.ini sets `qt_api=pyside6`, so pytest-qt is not optional here; it is
  # what makes the setting mean anything.  pytest-xvfb starts the virtual
  # display the OpenGL widgets need.
  #
  # `pytest-split` is in upstream's `tests` extra and is deliberately absent:
  # nixpkgs does not carry it, and it only shards a suite across CI workers —
  # nothing collects or asserts differently without it.  It is not referenced
  # from any test module, only from upstream's workflow files, so there is
  # nothing to patch out.
  #
  # libglvnd supplies libGL.so.1, which PyOpenGL dlopens by bare soname at
  # import time rather than linking against.
  preCheck = ''
    export HOME="$(mktemp -d)"
    export MPLBACKEND=Agg
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ libglvnd ]}''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
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
