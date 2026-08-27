{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  cffi,
  morfeus-ml,
  numpy,
  pandas,
  progress,
  pyyaml,
  rdkit,

  # See ../harmonwig/default.nix for why cclib is a defaulted argument and what
  # meta.broken below is protecting.  aqme/qcorr.py and aqme/qcorr_utils.py
  # both `import cclib` at module scope, so QCORR — one of the five workflow
  # stages — does not load without it.
  cclib ? null,

  # tests
  pytestCheckHook,

  # Defaulted for the same reason cclib is, but a different absence.  Both of
  # these are `pkgs.qchem.*` attributes from NixOS-QChem's overlay on the
  # package set this is actually built against, and xtb is *additionally* a
  # top-level attribute of nixpkgs-unstable while crest is not in nixpkgs at
  # all.  No single spelling resolves everywhere, so
  # ../../overlays/default.nix picks whichever the package set has and this
  # falls back to running fewer tests.
  xtb ? null,
  crest ? null,
}:

buildPythonPackage {
  pname = "aqme";
  version = "2.0.0-unstable-2026-07-06";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "jvalegre";
    repo = "aqme";
    rev = "4f52af455d8268fe139c9befcca71f243a26368e";
    hash = "sha256-vnx6uiSfh2cl3Topp0kKXDpjVu9ncmh+lzSUXnJkqi0=";
  };

  build-system = [ setuptools ];

  # Every one of upstream's eight requirements is an `==` pin on whatever was
  # current when 2.0.0 was cut — PyYAML==6.0.3, numpy==2.3.4, rdkit==2025.9.1
  # and so on.  That is a lockfile written into install_requires, not a
  # statement about incompatibility, and no version in the locked nixpkgs
  # matches any of them exactly.  Relaxing all of them wholesale is the only
  # workable reading; listing them individually would just restate setup.py.
  pythonRelaxDeps = true;

  dependencies = [
    cffi
    morfeus-ml
    numpy
    pandas
    progress
    pyyaml
    rdkit
  ]
  ++ lib.optional (cclib != null) cclib;

  nativeCheckInputs = [
    pytestCheckHook
  ]
  # tests/test_cmin.py and tests/test_qdescp.py shell out to xtb for
  # single-point energies and atomic descriptors; tests/test_csearch.py drives
  # CREST conformer searches through `subprocess.run(["crest", ...])`, and
  # reaches xtb as well.
  ++ lib.optional (xtb != null) xtb
  ++ lib.optional (crest != null) crest;

  # Each file is skipped only when the program it shells out to is absent, so
  # the whole suite runs on the package set that has NixOS-QChem's qchem.* —
  # which is the one ../../flake.nix actually builds this on.
  disabledTestPaths =
    lib.optionals (xtb == null) [
      "tests/test_cmin.py"
      "tests/test_qdescp.py"
    ]
    ++ lib.optional (xtb == null || crest == null) "tests/test_csearch.py";

  # The cmin and qdescp tests compare against reference numbers recorded from
  # one particular xtb build.  A mismatch there is version skew rather than a
  # broken package, and the fix is a `disabledTests` entry quoting the observed
  # values — not switching the suite off.
  pythonImportsCheck = [
    "aqme"
    "aqme.cmin"
    "aqme.qdescp"
    "aqme.qprep"
  ];

  meta = {
    description = "Automated Quantum Mechanical Environments — reproducible workflows for QM calculations";
    homepage = "https://github.com/jvalegre/aqme";
    changelog = "https://github.com/jvalegre/aqme/blob/master/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
    # Reachable only through the flake; see the cclib argument above.
    broken = cclib == null;
  };
}
