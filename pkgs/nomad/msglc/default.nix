{
  lib,
  buildPythonPackage,
  fetchPypi,
  rustPlatform,
  bitarray,
  cbor2,
  msgpack,
  universal-pathlib,
  # msglc[msgspec,s3fs] — the extras nomad-lab asks for
  msgspec,
  s3fs,
}:

buildPythonPackage rec {
  pname = "msglc";
  version = "260423";
  pyproject = true;

  # PyPI rather than GitHub: upstream publishes no git tags, so there is no
  # revision to pin, and the sdist ships no tests either way.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-4XP1YeOqoKho0MNJu8fyXceaXlihUORLbtnDVIK5X4U=";
  };

  # msglc/__init__.py imports .msglc_rust unconditionally, so the maturin
  # extension is not optional.
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit pname version src;
    # PLACEHOLDER.  A cargo vendor hash cannot be computed without realising a
    # fixed-output derivation, which the Claude Code sandbox cannot do (no
    # nix-daemon).  The first build outside the sandbox prints the real hash;
    # paste it here.  Cargo.lock has 19 crates.
    hash = "sha256-EJVtIzBaeK0us1KX7sroewHT8SkB2tz5nKGiE7uPh5Q=";
  };

  build-system = [
    rustPlatform.maturinBuildHook
    rustPlatform.cargoSetupHook
  ];

  dependencies = [
    bitarray
    cbor2
    msgpack
    universal-pathlib
    msgspec
    s3fs
  ];

  pythonImportsCheck = [
    "msglc"
    "msglc.msglc_rust"
  ];

  meta = {
    description = "Lazily loadable msgpack/cbor containers, NOMAD's archive storage format";
    homepage = "https://github.com/TLCFEM/msglc";
    license = lib.licenses.gpl3Plus;
    maintainers = [ lib.maintainers.berquist ];
  };
}
