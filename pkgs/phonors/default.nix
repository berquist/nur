{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  cargo,
  rustc,
  rustPlatform,
}:

buildPythonPackage (finalAttrs: {
  pname = "phonors";
  version = "0.5.0";
  pyproject = true;
  __structuredAttrs = true;

  # phonopy's and phono3py's Rust kernels, replacing nixpkgs' 0.3.0 in the
  # materials overlay for ../phonopy at `main`.  That declares `>=0.4.0`, but it
  # calls `grid_indices_from_addresses`, which 0.5.0 introduced in place of
  # 0.4's `grid_index_from_address`.  0.5.0 exports every name phonopy `main`
  # and ../phono3py call, 62 of them; 0.4.0 lacks that one.
  #
  # Hash from ../../scripts/offline-src-hash.sh against a clone in wc/phonors.
  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phonors";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XEQcvmZ/eA7k4fBkDz9DleC7mpwQAmaG5WysDRugSlc=";
  };

  # From the lock file rather than fetchCargoVendor, whose hash cannot be
  # computed without the network.  ./Cargo.lock is the v0.5.0 one verbatim,
  # and a copy rather than `${src}/Cargo.lock`, because reading a file out of a
  # fetched source at evaluation time is import-from-derivation.  It has no git
  # sources, so importCargoLock needs no `outputHashes`.
  cargoDeps = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };

  build-system = [
    cargo
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
    rustc
  ];

  # nixpkgs runs nothing here ("Module has no tests"), but the crate has 84
  # Rust tests, which upstream's CI runs as below.  `--no-default-features`
  # turns off pyo3's `extension-module`, which is what lets the test binary
  # link against libpython.
  checkPhase = ''
    runHook preCheck
    cargo test --offline --no-default-features
    runHook postCheck
  '';

  pythonImportsCheck = [ "phonors" ];

  meta = {
    description = "Rust kernels for phonopy and phono3py";
    homepage = "https://github.com/phonopy/phonors";
    changelog = "https://github.com/phonopy/phonors/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
