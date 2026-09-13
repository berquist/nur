{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  makeWrapper,

  # build-system
  hatchling,

  # dependencies
  openbabel-bindings,
  openbabel,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "openprattle";
  version = "1.2.0";
  pyproject = true;

  # HEAD is exactly the v1.2.0 tag; the project is not on PyPI.
  src = fetchFromGitHub {
    owner = "Digichem-Project";
    repo = "openprattle";
    rev = "v${version}";
    hash = "sha256-D37vsY7Y55efaX4tuIcqNXD65WaNbxNV5MdRFsLjfic=";
  };

  build-system = [ hatchling ];

  nativeBuildInputs = [ makeWrapper ];

  # Upstream's single `openbabel >= 3.0.0` requirement covers both halves of
  # what this package wraps, and it needs both.  openprattle/babel.py tries
  # `from openbabel import pybel` and, when that fails, falls back to spawning
  # the `obabel` executable — so the bindings alone would silently degrade
  # every conversion the bindings do not handle to a subprocess that is not
  # on PATH.  openbabel supplies that executable.
  dependencies = [ openbabel-bindings ];

  # `openbabel` is upstream's spelling of what `openbabel-bindings` provides,
  # and nixpkgs installs that package without a `.dist-info` — it is built from
  # CMake rather than as a wheel — so `pythonRuntimeDepsCheckHook` reports
  # "openbabel not installed" and fails the build, with the module sitting right
  # there in site-packages.
  #
  # The same defect as nixpkgs' rdkit, and handled the other way round: that one
  # is repaired once in ../../overlays/default.nix, because ten packages here
  # declare it.  openbabel is a much larger C++ build, nothing else here declares
  # it as a *dependency* (emmet-core, quacc and dpdata take it as a check input,
  # which this hook does not inspect), and rebuilding it would cost every
  # consumer a cache miss to add one METADATA file.  Dropping the declaration is
  # the shape ../ccreg uses, and the trade is written out at the rdkit binding.
  pythonRemoveDeps = [ "openbabel" ];

  # The fallback path resolves `obabel` off PATH at call time, which is empty
  # for a program launched from a systemd unit or another package's closure.
  postInstall = ''
    wrapProgram $out/bin/oprattle \
      --prefix PATH : ${lib.makeBinPath [ openbabel ]}
  '';

  nativeCheckInputs = [
    pytestCheckHook
    openbabel
  ];

  # test/test_prog.py is the CLI's own suite and runs `oprattle` as a
  # subprocess — nineteen tests, every one of them dying with
  # `FileNotFoundError: [Errno 2] No such file or directory: 'oprattle'` until
  # the script is on PATH.  The check phase runs after the install one, so
  # $out/bin exists and holds the wrapped script; putting it on PATH exercises
  # the wrapper as well as the program, which is the thing `postInstall` above
  # exists for.  Same fix as ../aiida-pseudo and ../aiida-gromacs.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  # test/test_formats.py is marked `formats` and upstream's conftest skips the
  # whole marker unless `--formats` is passed.  That is left alone deliberately:
  # those tests convert between every format Open Babel claims to support, and
  # openprattle/babel.py already carries a list of the ones broken in one
  # binding or the other.
  pythonImportsCheck = [
    "openprattle"
    "openprattle.babel"
  ];

  meta = {
    description = "Convenience wrapper around the pybel library and the obabel command-line tools";
    homepage = "https://github.com/Digichem-Project/openprattle";
    license = lib.licenses.gpl2Only;
    mainProgram = "oprattle";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
