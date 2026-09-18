{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  wheel,

  # dependencies
  aiida-core,
  qcelemental,
  sqlalchemy,

  # tests
  pytestCheckHook,
  aiida-testing,
  procps,
}:

buildPythonPackage {
  pname = "aiida-psi4";
  version = "0.1.0a0-unstable-2026-08-16";
  pyproject = true;

  # No tags and no PyPI release; `master` is where it has always lived.
  src = fetchFromGitHub {
    owner = "ltalirz";
    repo = "aiida-psi4";
    rev = "637e6b0b29e724a158014269d55d9091c6af48c7";
    hash = "sha256-JMdYxwU3z7cgOIgbzbKslxzcr3pKtKKSSRXSTSWc+v8=";
  };

  # There is no [project] table and no [build-system] table either — the whole
  # distribution is a legacy setup.py that json-loads setup.json and splats it
  # into setup().  `build` falls back to setuptools + wheel for exactly this
  # case, so they are named explicitly rather than left to a default.
  build-system = [
    setuptools
    wheel
  ];

  # This package is AiiDA-1.x-era metadata wrapped around AiiDA-2-compatible
  # code, and the two have to be reconciled by hand.
  #
  # `setup_requires: ["reentry"]` is the load-bearing removal: setuptools
  # resolves setup_requires by *downloading* at build time, which a fixed-output
  # build cannot do.  `reentry_register` is the hook that used to rebuild
  # AiiDA 1.x's entry-point cache and has no counterpart in 2.x, where entry
  # points are read from importlib.metadata directly.
  #
  # tests/test_data.py imports ValidationError from `pydantic.error_wrappers`,
  # the pydantic-1 location.  aiida-core pulls pydantic 2, where that module is
  # a migration stub that raises on attribute access — but qcelemental's v1
  # models (which AtomicInput is built on) validate through `pydantic.v1`, so
  # the exception the test wants really is the v1 one, just under its new name.
  #
  # `codeinfo.withmpi = self.inputs.metadata.options.withmpi` is the third, and
  # it is a line that has to go rather than be rewritten.  `metadata.options.
  # withmpi` is `required=False` with no default in aiida-core 2.x, so when
  # nothing sets it the key is simply absent and reading it raises through
  # plumpy's AttributesFrozendict:
  #
  #     AttributeError: 'AttributesFrozendict' object has no attribute 'withmpi'
  #     ... PreSubmitException: exception occurred in presubmit call
  #
  # Both examples die there, before Psi4 would have been reached.  A plugin is
  # no longer supposed to ask: CalcJob.presubmit collects the option, the
  # plugin's own `CodeInfo.withmpi` and the code's `with_mpi`, requires the ones
  # that are set to agree, and falls back to the option's default otherwise.
  # Leaving `CodeInfo.withmpi` as None is how a plugin says it does not care,
  # which for Psi4 — threaded, not MPI — is the truth.  Upstream aiida-diff
  # deleted the identical line in its own `updates for aiida 2.5`; see
  # ../aiida-diff for why this package set has that commit and not the tag.
  #
  # The last two hunks rename the recorded mock-code fixtures, for the same
  # reason ../aiida-testing renames its own: aiida-testing keys a cached result
  # by an md5 of the calculation's working directory, that directory contains
  # `_aiidasubmit.sh`, and aiida-core 2.10 does not write the 2021 submit script
  # byte for byte.  Both recorded digests therefore describe nothing, every
  # lookup misses, and each example retrieves a folder with only the scheduler's
  # own files in it:
  #
  #     QCSchemaParser: [ERROR] Found files '['_scheduler-stderr.txt',
  #       '_scheduler-stdout.txt']', expected to find '['output.json']'
  #     KeyError: 'qcschema'
  #
  # Nothing here produces the replacement digests for free, which is what makes
  # this harder than aiida-testing: conftest.py names no executable for the
  # `psi4-1.4rc2` label — the whole point, since there is no Psi4 — so a miss has
  # nothing to run and backs nothing up.  These two came from a build with a
  # `.aiida-testing-config.yml` naming `true` as that executable, which runs,
  # writes nothing, and backs the empty result up under the digest the lookup
  # wanted.  The input file left behind in each says which example it belongs
  # to: `input.json` is the qcschema one, example_01.
  #
  # To do that again after an aiida-core bump — the symptom will be these two
  # examples and nothing else — put the config back for one run:
  #
  #     printf 'mock_code:\n  psi4-1.4rc2: "true"\n' > .aiida-testing-config.yml
  #
  # written with printf rather than a heredoc, whose body would have to sit at
  # column 0 and would drag this whole string's indentation down with it, and
  # with "true" quoted, because YAML reads it as a boolean otherwise and the
  # config is validated against a voluptuous schema that wants a str.  Then
  #
  #     nix build -L --keep-failed .#python313Packages.aiida-psi4
  #     ls <kept build dir>/source/tests/data
  #
  # The example_01 hunk is what makes that digest hold on more than one channel
  # at a time, and it is worth understanding before touching either.  The md5 is
  # over the *working* directory, which for the qcschema example is
  # `_aiidasubmit.sh` plus the `input.json` the plugin writes — and that file is
  # `json.dumps` of a qcelemental model, which stamps its own version into two
  # provenance blocks:
  #
  #     "provenance": {"creator": "QCElemental",
  #                    "routine": "qcelemental.models.v1.results",
  #                    "version": "0.50.4"}
  #
  # So the digest is a function of the qcelemental version.  nixos-26.05 has
  # 0.50.0rc3 and both unstable channels have 0.50.4, and a diff of the two
  # serialised inputs shows those two strings and nothing else — same fields,
  # same values, same geometry.  That is exactly why example_02, whose input is
  # a literal PsiAPI string, passes on 26.05 while this one does not.
  #
  # Pinning both to the version the fixture was recorded against makes
  # `input.json` byte-identical everywhere.  On unstable it is a no-op, so the
  # digest above is unchanged; on 26.05 the input becomes unstable's and the
  # same digest starts hitting.  It also survives future qcelemental bumps,
  # which the digest otherwise would not.
  #
  # Pin only what actually differs.  `routine` moved from
  # `qcelemental.models.results` to `...models.v1.results` at some point after
  # the fixture's own `input.json` was recorded, but both live channels agree on
  # it today, so normalising it as well would change the digest rather than
  # preserve it.  Same for the geometry, which numpy round-trips identically.
  #
  # The pin goes through `set_dict` on the unstored node rather than into
  # TEST_DICT: qcelemental honours a provenance supplied at the top level but
  # regenerates the molecule's, because Molecule.__init__ re-stamps it through
  # molparse.from_schema.
  #
  # `jsonb_order` is the second half of the same argument, and it is what the
  # fixture migration above cost.  The digest is over the *bytes* of
  # `input.json`, which `_write_input_file` produces with a bare
  # `json.dumps(self.inputs.qcschema.get_dict(), indent=2)` — no `sort_keys` —
  # so the key order is whatever the storage backend hands back.  The
  # deprecated fixture plugin built its profile on `core.psql_dos`, whose
  # `jsonb` column reorders every object's keys by byte length and then
  # bytewise; `aiida.tools.pytest_fixtures` defaults to `core.sqlite_dos`,
  # which is plain JSON and echoes back whatever order the dict was built in.
  # Different order, different bytes, different md5, and the recorded directory
  # describes nothing again:
  #
  #     QCSchemaParser: [ERROR] Found files '['_scheduler-stderr.txt',
  #       '_scheduler-stdout.txt']', expected to find '['output.json']'
  #     KeyError: 'qcschema'
  #
  # The recorded `tests/data/mock-psi4-1.4rc2-8ee90fe.../input.json` is itself
  # proof of which order the digests were taken in: its top level runs
  # id, model, driver, extras, keywords, molecule, protocols, provenance,
  # schema_name, schema_version — length, then lexicographic, recursively, at
  # every level.  Sorting the dict that way before `set_dict` reproduces those
  # bytes exactly, so `24adc79085d1b8f0d854137ffa8076e6` keeps hitting.  It is
  # also idempotent under psql_dos, which would re-sort to the same order, so
  # this survives a move back the other way.
  #
  # example_02 is the control that says nothing *else* moved: its working
  # directory is `_aiidasubmit.sh` plus a literal PsiAPI string with no dict in
  # it, and its digest still hits across both the storage-backend change and
  # the aiida-core bump that came with it.  So the submit script is unchanged
  # and the key order is the whole of the difference.
  #
  # `key.encode()` rather than the str: jsonb orders by the key's UTF-8 byte
  # length and then by its bytes.  Every key here is ASCII, so it makes no
  # difference today — it is written this way so that a non-ASCII key added
  # upstream does not silently sort differently from the database that
  # recorded the fixture.
  postPatch = ''
    # See ../aiida-cp2k for why this is a rewrite rather than a version bump,
    # and why pgtest, postgresql and the locale export left with it.
    substituteInPlace conftest.py \
      --replace-fail 'aiida.manage.tests.pytest_fixtures' 'aiida.tools.pytest_fixtures' \
      --replace-fail \
        'def clear_database_auto(clear_database):' \
        'def clear_database_auto(aiida_profile_clean):'

    substituteInPlace setup.json \
      --replace-fail '"setup_requires": ["reentry"],' "" \
      --replace-fail '"reentry_register": true,' ""

    substituteInPlace tests/test_data.py \
      --replace-fail 'from pydantic.error_wrappers import ValidationError' \
                     'from pydantic.v1.error_wrappers import ValidationError'

    substituteInPlace aiida_psi4/calculations.py \
      --replace-fail \
        "        codeinfo.code_uuid = self.inputs.code.uuid
            codeinfo.withmpi = self.inputs.metadata.options.withmpi" \
        "        codeinfo.code_uuid = self.inputs.code.uuid"

    substituteInPlace examples/example_01.py \
      --replace-fail \
        "    atomic_input = AtomicInput(TEST_DICT)" \
        "    atomic_input = AtomicInput(TEST_DICT)

        def jsonb_order(value):
            if isinstance(value, dict):
                keys = sorted(value, key=lambda key: (len(key.encode()), key.encode()))
                return {key: jsonb_order(value[key]) for key in keys}
            if isinstance(value, list):
                return [jsonb_order(item) for item in value]
            return value

        pinned = atomic_input.get_dict()
        pinned['provenance']['version'] = '0.50.4'
        pinned['molecule']['provenance']['version'] = '0.50.4'
        atomic_input.set_dict(jsonb_order(pinned))"

    mv tests/data/mock-psi4-1.4rc2-8ee90fe88003087a30e5fa3bc31a1a44 \
       tests/data/mock-psi4-1.4rc2-24adc79085d1b8f0d854137ffa8076e6
    mv tests/data/mock-psi4-1.4rc2-2e539a93de20c9dd9464f293bb8bcc85 \
       tests/data/mock-psi4-1.4rc2-c3d9025f3730994a7ed9c9e7c030eaad
  '';

  # setup.json still declares `aiida-core>=1.6.4,<2.0.0`, `sqlalchemy<1.4` and
  # `qcelemental~=0.20.0`, all from 2021.  Every import in aiida_psi4/ —
  # aiida.engine, aiida.orm, aiida.plugins, aiida.parsers.parser, aiida.common —
  # is on the API that survived into 2.x, and the package does not touch
  # SQLAlchemy itself at all, so these are stale bounds rather than real ones.
  pythonRelaxDeps = [
    "aiida-core"
    "qcelemental"
    "sqlalchemy"
  ];

  dependencies = [
    aiida-core
    qcelemental
    sqlalchemy
  ];

  nativeCheckInputs = [
    pytestCheckHook

    # conftest.py loads `aiida_testing.mock_code` as a pytest plugin; see
    # ../aiida-testing for why that is a git-pinned fork rather than a release.
    aiida-testing
    # The `direct` scheduler polls with `ps`, and without it the joblist comes
    # back empty, the job is declared finished at once, and retrieval takes
    # whatever exists at that instant.  That is the two `_scheduler-*.txt`
    # files, which the submit script's own `exec >` redirection created before
    # anything ran, so the parser reports
    #
    #     Found files '['_scheduler-stderr.txt', '_scheduler-stdout.txt']',
    #     expected to find '['output.json']'
    #
    # and the example dies on the missing output.  This one is worth knowing by
    # its second symptom as well: the mock code's copy lands *after* the
    # retrieval, so the calculation's working directory looks complete when
    # inspected afterwards, and the whole thing reads like a cache that was
    # never consulted.  ../aiida-cp2k, ../aiida-octopus and ../aiida-testing
    # each lost a calculation to the same missing program.
    procps
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # Upstream's addopts is `--durations=0 --cov=aiida_psi4`, which needs
  # pytest-cov for output that is thrown away.  Same treatment as aiida-core.
  pytestFlags = [ "--override-ini=addopts=" ];

  # `testpaths` covers tests/ *and* examples/, and `python_files` is widened to
  # match `example_*.py`, so both are collected — deliberately, and it works
  # here: the examples run through aiida-testing's mock code, which replays the
  # stored Psi4 output under tests/data/ instead of executing anything.  No Psi4
  # binary is involved, which is the whole point of the mock_code fixture.

  pythonImportsCheck = [
    "aiida_psi4"
    "aiida_psi4.data"
    "aiida_psi4.calculations"
    "aiida_psi4.parsers"
  ];

  meta = {
    description = "AiiDA plugin for the Psi4 quantum chemistry package";
    homepage = "https://github.com/ltalirz/aiida-psi4";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
