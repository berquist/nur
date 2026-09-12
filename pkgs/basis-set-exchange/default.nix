{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  argcomplete,
  jsonschema,
  regex,
  unidecode,

  # tests
  pytestCheckHook,
  pytest-xdist,
  numpy,

  # wignernj, the other half of the `tests` extra, and this repository has it —
  # ../wignernj, in the chemtools overlay.  Defaulted rather than required
  # because the two overlays are composed separately in places: `tests/`'s
  # cheminformatics suite builds `cheminformatics` and `cheminformatics-cclib`
  # alone, with no chemtools in the fixpoint, and a hard argument would make
  # this package unevaluable there.  ../../overlays/default.nix fills it from
  # `pself.wignernj or null`, so the full composition — which ../../default.nix
  # and CI both use — runs the tests, and a narrower one skips them as before.
  wignernj ? null,
}:

buildPythonPackage rec {
  pname = "basis-set-exchange";
  # PEP 440 rather than the usual `-unstable-YYYY-MM-DD`: this string is handed
  # to setuptools-scm as SETUPTOOLS_SCM_PRETEND_VERSION below, and it rejects
  # anything the packaging library cannot parse.
  version = "0.12.dev20260807";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MolSSI-BSE";
    repo = "basis_set_exchange";
    rev = "4adaf1372c7101620ca1a9f3130be9ae97fb8f30";
    hash = "sha256-KShYrcrN9QpC8DDJvSCKOZFwV+QpcnjNBAGPVb4Zcdk=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  # setuptools-scm reads the version out of git, and fetchFromGitHub hands over
  # a tree with no .git.  Without this the build fails outright rather than
  # falling back, because upstream declares `dynamic = ["version"]` with no
  # fallback configured.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  dependencies = [
    argcomplete
    jsonschema
    regex
    unidecode
  ];

  # `wignernj` completes the `tests` extra.  It is used only by the
  # spherical-harmonic transformation tests, which skip themselves when the
  # import fails — and a skip is indistinguishable from a pass in a build log,
  # which is why it is worth filling in rather than leaving to degrade.  See the
  # argument above for why it is defaulted.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-xdist
    numpy
  ]
  ++ lib.optional (wignernj != null) wignernj;

  # pytest-xdist, because this suite is a good fit for it: every test is
  # parametrised over an independent basis set, there is no shared state and no
  # ordering between them, and nothing writes outside pytest's `tmp_path`.  The
  # default suite takes 50 s at 32 workers.
  #
  # **Upstream's `--runslow` is deliberately *not* passed, and that is a measured
  # decision rather than a cautious one.**  `tests/conftest.py` defines it, and
  # without it `pytest_ignore_collect` drops all eight `*_slow.py` modules and
  # `pytest_collection_modifyitems` skips anything marked `slow`.  Turning it on
  # collects 798,417 tests and takes 4 h 12 m even at 32 workers, for
  # 10,201 failures — and they are upstream's own converter limits rather than
  # anything packaging did: 6,144 are `Converter {veloxchem,fhiaims} does not
  # support all function types`, 1,568 are `ECP contains l=5 term but Crystal
  # format only supports up to ...`, 576 are `Electrons cover a partial shell`.
  # Triaging that is a project, not a check phase.  See "basis-set-exchange's
  # --runslow suite" in ../../docs/TODO.md.
  #
  # The two skips that survive without it, since the question comes up every
  # time:
  #
  #   `test_qcschema.py`'s two tests gate on `_has_qcschema`, and `qcschema` —
  #   MolSSI's JSON-schema definitions, distinct from `qcelemental`, which
  #   nixpkgs does have — is not in nixpkgs.  Packaging it would buy less than
  #   it looks: both tests also carry `@pytest.mark.xfail`, so upstream already
  #   expects them to fail, and the result would be two xfails rather than two
  #   passes.
  #
  #   one bibtex test gates on `check_bibtex.available`, which is
  #   `shutil.which('bibtex') and shutil.which('latex')`.  That is a TeX
  #   installation as a check input for a single test, and it is not worth the
  #   closure.
  #
  # basis_set_exchange/tests/test_curate.py drives the `bsecurate` CLI against
  # the authoritative source data and is slow rather than fragile; it stays in.

  # **The suite runs from the installed tree, not the unpacked one.**
  #
  # `cd $out` because the tests live *inside* the package, which rules out the
  # `rm -rf <package>` that ../dpdata, ../parmed, ../sella and ../wignernj use
  # against the same trap: deleting the source copy here would delete the suite
  # with it.  Running from site-packages is the other way to be sure the tests
  # import what was installed rather than what was unpacked — and for this
  # package that is the check worth having, since most of what the wheel has to
  # carry is the `data/` tree of basis sets rather than code.  Safe to run from a
  # read-only store path: every test that writes goes through pytest's
  # `tmp_path`.
  preCheck = ''
    cd "$out/${python.sitePackages}"
  '';

  # Named rather than left to default, because the working directory above is
  # site-packages and a bare `pytest` there would sweep whatever else happens to
  # be beside the package.  It doubles as the usual canary: the hook expands
  # this as a glob and aborts when it matches nothing, so a wheel that stopped
  # shipping its tests would fail the build rather than pass zero of them.
  enabledTestPaths = [ "basis_set_exchange/tests" ];

  pythonImportsCheck = [
    "basis_set_exchange"
    "basis_set_exchange.misc"
    "basis_set_exchange.writers"
  ];

  meta = {
    description = "Basis Set Exchange — a library and CLI for quantum chemistry basis sets";
    homepage = "https://github.com/MolSSI-BSE/basis_set_exchange";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
