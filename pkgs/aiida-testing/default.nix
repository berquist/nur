{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  fastentrypoints,
  setuptools,

  # dependencies
  aiida-core,
  click,
  pyyaml,
  pytest,
  voluptuous,

  # tests
  pytestCheckHook,
  aiida-diff,
  diffutils,
  pgtest,
  postgresql,
  procps,
  pytest-datadir,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage {
  pname = "aiida-testing";
  version = "0.1.0-unstable-2021-05-06";
  pyproject = true;

  # Exactly the revision aiida-psi4's setup.json pins in its `testing` extra:
  #
  #   "aiida-testing @ git+https://github.com/ltalirz/aiida-testing@6b3c2ae...
  #
  # It provides the `mock_code_factory` fixture that aiida-psi4's conftest uses
  # to replay stored Psi4 outputs, which is what lets that package's tests run
  # with no Psi4 binary present.  There is no PyPI release of this fork.
  src = fetchFromGitHub {
    owner = "ltalirz";
    repo = "aiida-testing";
    rev = "6b3c2ae023157e73563630aaf24d8337c348b74b";
    hash = "sha256-2+M7E3Hj6Mh/7k6TrAte68+u5KmxHWVaF1tAbMU0pZs=";
  };

  # pyproject.toml asks for `fastentrypoints` alongside setuptools, and
  # pypaBuildPhase builds `--no-isolation`, so pythonRuntimeDepsCheckHook
  # refuses the wheel without it:
  #
  #     ERROR Unmet dependencies: fastentrypoints  wanted: any
  #                                                found: not installed
  #
  # setup.py imports it inside a try/except that only warns, so dropping it from
  # the requires list would work too.  It is cheap and nixpkgs has it, so it is
  # supplied rather than patched away — one fewer place where this package
  # differs from what upstream declares.
  build-system = [
    fastentrypoints
    setuptools
  ];

  # setup.cfg writes `aiida-core>=1.0.0<2.0.0`, with no comma between the two
  # specifiers.  packaging accepted that for years and 26.2 does not, so the
  # build dies inside pypaBuildPhase, before any of this package's own code
  # runs, in setuptools' _normalize_requires:
  #
  #     packaging.requirements.InvalidRequirement: Expected comma (within
  #     version specifier), semicolon (after version specifier) or end
  #         aiida-core>=1.0.0<2.0.0
  #                   ~~~~~~~^
  #
  # `pythonRelaxDeps` below cannot help: that hook rewrites Requires-Dist lines
  # in the built wheel's METADATA, and the failure is that there is no wheel.
  # Adding the comma is the smallest edit that lets the metadata parse at all;
  # the relaxation then drops the bound, as it was always going to.
  #
  # The second hunk is a Python 3.10 removal this 2021 fork never saw.
  # `collections.Iterable` has been the alias rather than the class since 3.3
  # and stopped existing in 3.10, so `mock_code_factory` raises
  #
  #     AttributeError: module 'collections' has no attribute 'Iterable'
  #
  # on the argument check every one of its callers goes through.  `import
  # collections` is enough to reach `collections.abc`, so the module's existing
  # import needs no companion.
  #
  # The third is the repository's own .aiida-testing-config.yml, which maps the
  # code label `diff` to the absolute path /usr/bin/diff.  A build sandbox has
  # no /usr/bin, and `mock_code_factory` reads that path straight out of the
  # file — nothing consults PATH — so putting diffutils in nativeCheckInputs
  # does not reach it.
  #
  # What that costs is invisible from the outside.  When the mock code finds no
  # cached result for the hash it computed, it runs the configured executable;
  # `subprocess.call` on a path that does not exist raises, so the mock code
  # dies and writes nothing.  But the submit script has already created
  # patch.diff by redirecting stdout into it, and aiida-diff's parser is happy
  # with a file that exists, so the calculation is `finished_ok` with
  # exit_status 0 and the assertion that fails is the one about the *contents*:
  #
  #     AssertionError: assert () == ('1,2c1', '< ...silly walks.')
  #
  # Only the label `diff` is rewritten.  `diff-broken` has no entry on purpose —
  # test_broken_code_require asserts that a missing entry raises — so the file
  # keeps saying nothing about it.
  #
  # The fourth hunk renames the two recorded fixture directories.  The mock code
  # looks for its cached result under `mock-{label}-{md5}`, where the md5 is over
  # the working directory — the two input files and `_aiidasubmit.sh`, the latter
  # stripped of the mock-code exports and of its own absolute path.  aiida-core
  # 2.10 does not generate the 2021 submit script byte for byte, so the digest
  # recorded in 2021 no longer describes anything and both directories miss.
  #
  # Only test_broken_code says so.  A miss falls through to running the
  # configured executable, which the other five can do and it cannot — the label
  # `diff-broken` has no entry in the config file on purpose.  "Works also when
  # no executable is given, if the result exists already" is exactly the case a
  # stale digest breaks, and the sibling tests going green on the fallback is
  # what hid it.  Renaming also puts test_basic back to testing what it says it
  # does: take the data from cache, rather than quietly recompute it.
  #
  # The digest is a fact about a build rather than something derivable here, and
  # the build is what produces it: on its own miss, test_basic writes the fresh
  # result back as `tests/mock_code/data/mock-diff-<digest>`.  It does not depend
  # on the label — upstream's two directories sharing one suffix is the evidence,
  # and these two do too.  When a future aiida-core changes the submit script
  # again, test_broken_code will fail alone once more, and
  #
  #     nix build -L --keep-failed .#python313Packages.aiida-testing
  #     ls <kept build dir>/source/tests/mock_code/data
  #
  # names the replacement.  `mv` rather than a copy, so a digest that has moved
  # on fails the build instead of leaving the old directory to be found.
  postPatch = ''
    substituteInPlace setup.cfg \
      --replace-fail "aiida-core>=1.0.0<2.0.0" "aiida-core>=1.0.0,<2.0.0"

    substituteInPlace aiida_testing/mock_code/_fixtures.py \
      --replace-fail "collections.Iterable" "collections.abc.Iterable"

    substituteInPlace .aiida-testing-config.yml \
      --replace-fail "diff: /usr/bin/diff" "diff: ${diffutils}/bin/diff"

    recorded=4b5ca93b23993979a24f795147487f1c
    current=6386440b94ffb782bb19e6b2f19283c8
    for label in diff diff-broken; do
      mv "tests/mock_code/data/mock-$label-$recorded" \
         "tests/mock_code/data/mock-$label-$current"
    done
  '';

  # The pin is from 2021 and names aiida-core 1.x; the fixtures themselves use
  # the plugin API that survived into 2.x.  This is the riskiest relaxation in
  # the repo — if aiida-testing turns out not to import against 2.10 at all,
  # this package and aiida-psi4's checkPhase are what will say so.
  pythonRelaxDeps = true;

  dependencies = [
    aiida-core
    click
    pyyaml
    pytest
    voluptuous
  ];

  preCheck = ''
    export PATH="$out/bin:$PATH"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  # setup.cfg's `testing` extra is `pgtest`, `pytest-datadir` and `aiida-diff`.
  # The second supplies the `datadir` fixture that tests/mock_code/test_diff.py
  # asks for; without it four of its six tests error at setup with
  # "fixture 'datadir' not found", which is a missing dependency wearing the
  # costume of a broken test.
  #
  # The third registers the `diff` entry points that all six tests in
  # tests/mock_code/test_diff.py build a code against; it is in nixpkgs no more
  # than this package is, so ../aiida-diff packages it.
  #
  # `diffutils` is not in that extra and is needed anyway: test_inexistent_data
  # deliberately gives the mock code an empty data directory, which is the path
  # where it stops mocking and runs the real executable.
  #
  # `procps` is the same again.  Every one of these four tests runs a real
  # calcjob through the `direct` scheduler, cached or not, and without `ps` the
  # joblist comes back empty and the retrieval happens before anything has been
  # written.  It does not fail — it hands the parser an empty file, and what
  # lands is
  #
  #     AssertionError: assert () == ('1,2c1', '< ...silly walks.')
  #
  # which reads like a diff that produced the wrong text rather than a job that
  # was never waited for.  ../aiida-cp2k and ../aiida-octopus each lost a
  # calculation to this.
  nativeCheckInputs = [
    pytestCheckHook
    pgtest
    postgresql
    pytest-datadir
    aiida-diff
    diffutils
    procps
  ];

  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  pythonImportsCheck = [
    "aiida_testing"
    "aiida_testing.mock_code"
  ];

  meta = {
    description = "pytest fixtures for testing AiiDA plugins, including mock codes";
    homepage = "https://github.com/ltalirz/aiida-testing";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
