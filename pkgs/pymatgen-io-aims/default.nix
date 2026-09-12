{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,

  # dependencies
  pyfhiaims,
  pymatgen-core,

  # tests
  pytestCheckHook,
  monty,
  numpy,
}:

# pymatgen-io-aims — FHI-aims input and output support for pymatgen, and the
# fourth distribution in this repository to install into the `pymatgen/` tree.
#
# **It is not an add-on that was always separate; it is a piece pymatgen shed.**
# The 2026 split moved `pymatgen/io/aims/` out of the core distribution along
# with `pymatgen/io/fleur/`, and `pymatgen-core` now carries only compatibility
# shims for the two — see the "Compatibility shims for external namespace
# packages" section at the end of its `src/pymatgen/io/registry.py`, whose
# `_aims_read_str` and `_aims_write_str` import from here lazily.  So
# `Structure.from_file("geometry.in")` works or does not work in a given
# environment depending on whether this package is installed.
#
# Here for ../atomate2, which names it in an `aims` extra and whose
# `tests/aims/conftest.py` imports `pymatgen.io.aims.sets.base` at module
# scope.  See ../pymatgen-core's header for how four distributions share one
# import path without colliding.
buildPythonPackage (finalAttrs: {
  pname = "pymatgen-io-aims";
  version = "0.2.1";
  pyproject = true;
  __structuredAttrs = true;

  # The only tag the repository has, and it is HEAD.  GitLab, like ../pyfhiaims
  # beneath it — both are FHI-aims-club projects.
  src = fetchFromGitLab {
    owner = "FHI-aims-club";
    repo = "pymatgen-io-aims";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KoYJlvCdtvdxZVjCq7XczZouCHlv4OTam9e+GUMsXyg=";
  };

  build-system = [ setuptools ];

  # Upstream asks for `pymatgen>=2022.0.3`, a floor written four years before
  # the split and so naming the distribution that no longer holds what this
  # imports.  Every pymatgen module it touches — `pymatgen.core`,
  # `pymatgen.io.core`, `pymatgen.symmetry.bandstructure` — is in
  # ../pymatgen-core, and none is in the ../pymatgen half.
  #
  # Rewritten rather than dropped with `pythonRemoveDeps`, because the
  # requirement is *wrong* rather than unwanted and there is a right answer to
  # put in its place.  Dropping it would leave the wheel's metadata claiming no
  # pymatgen at all and `pythonRuntimeDepsCheckHook` with nothing to check;
  # rewriting keeps that hook doing real work, which is what caught this in the
  # first place ("- pymatgen not installed", after a wheel that built cleanly).
  #
  # `2026.7.16` is the first pymatgen-core release, which is also the floor
  # ../quacc and upstream's own `pymatgen` metapackage use.  There is no
  # pymatgen-core answering to 2022.0.3 — the distribution did not exist.
  # ../pymatgen-io-validation needs none of this: upstream updated it for the
  # split and it declares `pymatgen-core` itself.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"pymatgen>=2022.0.3"' '"pymatgen-core>=2026.7.16"'
  '';

  dependencies = [
    pyfhiaims
    pymatgen-core
  ];

  nativeCheckInputs = [
    pytestCheckHook
    monty
    numpy
  ];

  # `tests/io/aims/conftest.py` reaches its fixtures through pymatgen's
  # `TEST_FILES_DIR`, not through a path relative to itself — the two autouse
  # fixtures point `AIMS_SPECIES_DIR` at `{TEST_FILES_DIR}/io/aims/species_directory`.
  # That constant defaults to pymatgen's own checkout, which is not what is
  # unpacked here, so without the override every test looks for its species
  # defaults inside ../pymatgen-core's source tree and finds nothing.  This
  # repository ships the files it needs under `tests/files/io/aims/`, in the
  # same layout.  ../pymatgen-core and ../pymatgen export the same variable at
  # their own directories, for the same reason.
  preCheck = ''
    export PMG_TEST_FILES_DIR="$(realpath ./tests/files)"
  '';

  pythonImportsCheck = [
    "pymatgen.io.aims"
    "pymatgen.io.aims.inputs"
    "pymatgen.io.aims.outputs"
    "pymatgen.io.aims.sets.base"
    "pymatgen.io.aims.sets.bs"
    "pymatgen.io.aims.sets.core"
    "pymatgen.io.aims.sets.magnetism"
  ];

  meta = {
    description = "FHI-aims input and output support for pymatgen";
    homepage = "https://gitlab.com/FHI-aims-club/pymatgen-io-aims";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
