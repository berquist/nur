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
