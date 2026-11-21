{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  cargo,
  rustc,
  rustPlatform,
}:

# phonors — the Rust kernels behind phonopy and phono3py.  Dist and import are
# both `phonors`.
#
# A guarded backport, shaped like ../monty: nixpkgs carries phonors, but no
# channel here is new enough.  ../phonopy 4.10 declares `phonors>=0.6.0`, and
# the floor is real rather than cosmetic — phonopy imports it in some thirty
# places, and 0.6.0 is where the `degenerate_ids` argument that phono3py's
# collision kernels pass first appeared.  The locked nixpkgs has 0.3.0 and the
# newest channel 0.5.0.  See the `phonors` binding in ../../overlays/default.nix
# for when the channel's own copy is taken instead.
#
# 0.8.0 rather than 0.6.0: everything after 0.6.0 is either phelel's (the spin
# and Fourier-binning kernels) or `bz_grid_addresses` going parallel with
# bit-identical output, per upstream's CHANGELOG.  Nothing phonopy calls changed
# shape.
buildPythonPackage (finalAttrs: {
  pname = "phonors";
  version = "0.8.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "phonopy";
    repo = "phonors";
    tag = "v${finalAttrs.version}";
    hash = "sha256-iX2w/rwes1uArpVEk6Jpqunm1kqr1dZAHVbucp9js6I=";
  };

  # Not computable offline: the vendor directory is 88 crates fetched from
  # crates.io.  `lib.fakeHash` until the first build reports the real one —
  # ../../scripts/refresh-hashes.sh reads it back out of the mismatch.
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = "sha256-cdBeKA6uVbmqbKASjfBi/fdSFVrWF520YLtY0EHDxsI=";
  };

  build-system = [
    cargo
    rustPlatform.cargoSetupHook
    rustPlatform.maturinBuildHook
    rustc
  ];

  # No Python tests upstream.  The crate does carry `#[cfg(test)]` modules, but
  # running them is untried: pyo3's `extension-module` feature, on by default
  # here, leaves the Python symbols for the interpreter to supply, which usually
  # stops `cargo test` from linking.  The real coverage is ../phonopy's and
  # ../phono3py's suites, which reach phonors from every dynamical-matrix, grid
  # and collision path.
  doCheck = false;

  pythonImportsCheck = [ "phonors" ];

  meta = {
    description = "Rust kernels for phonopy and phono3py";
    homepage = "https://github.com/phonopy/phonors";
    changelog = "https://github.com/phonopy/phonors/blob/${finalAttrs.src.tag}/CHANGELOG.md";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
