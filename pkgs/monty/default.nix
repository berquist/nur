{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  numpy,
  ruamel-yaml,

  # optional-dependencies
  ipython,
  msgpack,
  orjson,
  pandas,
  pint,
  pydantic,
  pymongo,
  torch,
  tqdm,

  # tests
  pytest-benchmark,
  pytestCheckHook,
}:

# A backport, not a package of ours, and it exists for exactly one reason:
# ../pymatgen-core declares `monty>=2026.7.16`, and the nixpkgs pinned in
# ../../flake.lock carries 2025.3.3.  That is not a pin this repo can relax
# away.  pythonRuntimeDepsCheckHook fails the wheel outright --
#
#     Checking runtime dependencies for pymatgen_core-2026.8.13-*.whl
#       - monty>=2026.7.16 not satisfied by version 2025.3.3
#
# -- and the seventeen months between the two releases contain the json.py
# rewrite (MSONable dispatch moved onto TypeHandler classes) that pymatgen-core
# serialises everything through, so relaxing it would trade a build failure for
# a runtime one.
#
# There can only be one monty in a package set: the import path is `monty`
# either way, so two derivations collide in any environment holding both.  That
# is why the materials overlay makes this a plain member of its extension
# rather than the `let`-bound, threaded-in shape ../../overlays/default.nix
# uses for pymatgenFor -- the pattern that keeps an override invisible to the
# rest of a consumer's package set does not work for a name every consumer
# already has.
#
# The binding there is guarded, so a channel that already carries 2026.7.16 or
# newer keeps its own and this file goes unused on that leg.  **Delete it once
# every leg of ../../Justfile's `channels` is past that version**, and drop the
# binding with it.  The aiida overlay's `monty` binding is the thing to check
# first: it already keys on this exact version, patching pandas 3 support into
# anything older and the bson defect below into anything newer, so the day
# nixpkgs catches up its `else` branch does the whole job.
buildPythonPackage (finalAttrs: {
  pname = "monty";
  version = "2026.7.16";
  pyproject = true;
  __structuredAttrs = true;

  # The tag, which is also HEAD of upstream's main as of 2026-08-30.
  src = fetchFromGitHub {
    owner = "materialsvirtuallab";
    repo = "monty";
    tag = "v${finalAttrs.version}";
    hash = "sha256-x5FNw7E3rtrgCWVhMsBpnO+uwu+mB3ELNFdd33+uFds=";
  };

  # The bson defect the aiida overlay's `monty` binding describes at length,
  # carried here because this file is what that binding's `else` branch would
  # otherwise be patching.  In short: `_DECODER_HANDLERS` registers BsonHandler
  # whether or not `import bson` succeeded, `BsonHandler.matches` checks
  # `bson is None` but `BsonHandler.decode` does not, so decoding a serialised
  # ObjectId without pymongo installed raises AttributeError instead of the
  # ImportError the dispatch site's own `except` clause is written to catch.
  #
  # It matters here rather than in monty's own suite because nixpkgs hands
  # monty its whole `optional` extra to test with, pymongo included, so `bson`
  # is never None there.  pymatgen-core declares no pymongo -- upstream
  # pymatgen does not either -- and tests/io/vasp/test_sets.py holds a
  # serialised ObjectId in a fixture.
  #
  # See ../../overlays/default.nix (the `monty` binding in the aiida overlay)
  # for the full reasoning; this is the same substitution, applied at the
  # source rather than through an override.
  # The second hunk is the mirror image of the pandas problem the aiida
  # overlay's pre-2026.7.16 branch describes, and it lands on the one leg that
  # builds this file.
  #
  # `_check_type` matches on `f"{cls.__module__}.{cls.__qualname__}"` over the
  # MRO, and pandas 3.0 decorates DataFrame and Series with
  # `@set_module("pandas")` where pandas 2 does not.  So the qualified name is
  # "pandas.DataFrame" under 3 and "pandas.core.frame.DataFrame" under 2.
  # 2026.7.16's rewrite handles both -- `PandasHandler._DF_QUALNAMES` and
  # `_SERIES_QUALNAMES` are two-spelling tuples -- so the *library* is correct
  # either way and nothing needs patching there.  Its test module was not
  # updated to match: `TestCheckType::test_pandas` asserts the pandas 3
  # spelling alone and fails under pandas 2 with
  #
  #     assert _check_type(df, "pandas.DataFrame")
  #     E  AssertionError: assert False
  #
  # This is not an occasional failure.  ../../overlays/default.nix builds this
  # derivation only where the channel's own monty is older than 2026.7.16,
  # which today is nixos-26.05 alone, and that is exactly the leg carrying
  # pandas 2.3.3 -- the two unstable legs take the channel's monty and are
  # already on pandas 3.0.4.  So the test as shipped can never pass anywhere
  # this file is used.
  #
  # Given the tuples the library defines, the assertions get the same tuples
  # rather than the other spelling: true under either pandas, and testing what
  # `PandasHandler` actually calls instead of one spelling of it.  That is the
  # same reasoning, and the same shape, as the older branch in
  # ../../overlays/default.nix -- which is worth keeping in step, since it is
  # the code that replaces this file when 26.05 leaves the matrix.
  postPatch = ''
    substituteInPlace src/monty/json.py \
      --replace-fail \
        '        if d["@class"] == "ObjectId":' \
        '        if bson is None:
                raise ImportError("bson is not installed")
            if d["@class"] == "ObjectId":'

    substituteInPlace tests/test_json.py \
      --replace-fail 'assert _check_type(df, "pandas.DataFrame")' \
                     'assert _check_type(df, ("pandas.core.frame.DataFrame", "pandas.DataFrame"))' \
      --replace-fail 'assert _check_type(series, "pandas.Series")' \
                     'assert _check_type(series, ("pandas.core.series.Series", "pandas.Series"))'
  '';

  # pyproject.toml carries a literal `version`, so setuptools-scm does no
  # versioning work here and needs no PRETEND variable.  It is still in
  # `requires`, so it is still a build-system input.
  build-system = [
    setuptools
    setuptools-scm
  ];

  # msgpack was a hard dependency through 2025.3.3 and is the `serialization`
  # extra from 2026.2.18 on, which is why nixpkgs' derivation lists it here and
  # this one does not.  numpy went the other way: monty.json imports it
  # unconditionally and 2026.2.18 made that declaration honest.
  dependencies = [
    numpy
    ruamel-yaml
  ];

  optional-dependencies = {
    # Upstream's comment: "dev is for the `dev` module, not for development".
    dev = [ ipython ];
    json = [
      orjson
      pandas
      pint
      pydantic
      pymongo
      torch
    ];
    multiprocessing = [ tqdm ];
    serialization = [ msgpack ];
  };

  # The whole optional set, the way nixpkgs tests this: every one of them buys
  # back a real module.  pymongo is the load-bearing one -- without it
  # tests/test_json.py's bson round trips skip, which is precisely the coverage
  # gap that let the defect patched above through in the first place.
  #
  # pytest-benchmark is on top of that list rather than in it: tests/
  # test_benchmarks.py takes a `benchmark` fixture, and without the plugin the
  # module errors at collection rather than skipping.
  nativeCheckInputs = [
    pytest-benchmark
    pytestCheckHook
  ]
  ++ finalAttrs.passthru.optional-dependencies.dev
  ++ finalAttrs.passthru.optional-dependencies.json
  ++ finalAttrs.passthru.optional-dependencies.multiprocessing
  ++ finalAttrs.passthru.optional-dependencies.serialization;

  pythonImportsCheck = [
    "monty"
    "monty.json"
    "monty.serialization"
  ];

  meta = {
    description = "Serves as a complement to the Python standard library by providing a suite of tools to solve many common problems";
    homepage = "https://github.com/materialsvirtuallab/monty";
    changelog = "https://github.com/materialsvirtuallab/monty/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
