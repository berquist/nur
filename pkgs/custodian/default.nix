{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  monty,
  psutil,
  ruamel-yaml,

  # tests
  pytestCheckHook,
  pymatgen,
}:

buildPythonPackage rec {
  pname = "custodian";
  version = "2025.12.14-unstable-2026-08-03";
  pyproject = true;

  # A commit rather than the v2025.12.14 tag: the tag is eight months behind
  # HEAD, and quacc's `custodian>=2025.12.14` is satisfied either way.  The
  # sdist would also do — tests/ is shipped — but a git pin keeps this
  # consistent with the rest of the tree and with `nix-update`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "custodian";
    rev = "bb78390b4a9560d7268bc88455a1b8f3f72fef95";
    hash = "sha256-v5CjuqOkSvr9x/fY7tk10dAOgDAiMShYY4ANAMr71oE=";
  };

  # `TestVaspNpTMDValidator::test_check_and_correct` fails on
  # `assert handler.check()`, and the cause is a library bug rather than a test
  # one, so this fixes the library.
  #
  # `custodian.vasp.io.load_outcar` is wrapped in `tracked_lru_cache`, which
  # makes the argument it is called with the cache key.  Every caller in
  # `vasp/handlers.py` and `vasp/validators.py` -- eighteen of them -- builds
  # that argument as `os.path.join(directory, "OUTCAR")` with `directory`
  # defaulting to `"./"`, so the key is the constant string `"./OUTCAR"`
  # whatever directory the process is in.  Anything that chdirs between two
  # checks gets the first directory's parsed output back for the second.
  #
  # The test walks three fixture directories by `os.chdir` in one function, and
  # `npt_bad_vasp` is precisely the one whose OUTCAR has no MDALGO line -- how
  # a VASP built without `-Dtbdyn` gives itself away.  It receives
  # `npt_common`'s cached Outcar instead and reports the run as good.
  #
  # Note what is *not* involved: `check()` reads the INCAR and OUTCAR text
  # files that ship in `tests/files`, and never runs or looks for a VASP
  # binary.  Nothing here needs VASP installed.
  #
  # The patch moves the caching to a private inner function and has the public
  # one resolve the path first, so all eighteen call sites are fixed at once
  # and both signatures stay as they were.  Normalising inside the existing
  # function cannot work: the key is computed from the argument before the body
  # runs.  See the patch header for the full account -- it is written to be
  # sent upstream as-is.
  patches = [ ./cache-key-abspath.patch ];

  build-system = [ setuptools ];

  dependencies = [
    monty
    psutil
    ruamel-yaml
  ];

  # pymatgen is a *test* dependency only — upstream keeps it out of
  # `dependencies` and offers it as the `matsci` extra, because the core
  # error-handling machinery does not import it.  Seven of the twenty-one test
  # modules do (vasp, qchem, cp2k, feff), so leaving it out would quietly
  # reduce the suite to the two top-level modules.
  #
  # `pymatgen` here is the materials overlay's, which is upstream's post-split
  # metapackage rather than nixpkgs' 2025.10.7 monolith — see
  # ../pymatgen-core.  It used to be threaded in by hand from a `let` binding
  # that lifted nixpkgs' `disabled = pythonAtLeast "3.13"` gate; the
  # replacement carries no such gate, so the set's own attribute now resolves
  # to the right thing on its own.
  nativeCheckInputs = [
    pytestCheckHook
    pymatgen
  ];

  pythonImportsCheck = [
    "custodian"
    "custodian.custodian"
  ];

  meta = {
    description = "Just-in-time job management and error correction for scientific calculations";
    homepage = "https://github.com/materialsproject/custodian";
    changelog = "https://github.com/materialsproject/custodian/blob/master/docs/changelog.md";
    license = lib.licenses.mit;
    mainProgram = "cstdn";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
