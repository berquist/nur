# python-overrides.nix — everything NOMAD needs that nixpkgs does not have, or
# has at the wrong version.
#
# This is the `packageOverrides` of a *scoped* interpreter (see
# ../../overlays/nomad.nix), not a pythonPackagesExtensions entry.  That is the
# whole point: NOMAD needs fastapi 0.136, httpx 0.27, plotly 5, beautifulsoup4
# 4.12, rdflib 5 and elasticsearch 7, and pushing those into every pythonX.pkgs
# would rebuild a large fraction of nixpkgs and break the QCArchive closure
# next door for no benefit.  Confining them to one interpreter costs a
# duplicated Python closure and buys not having to care.
#
# Three kinds of entry live here, in this order:
#
#   1. versions taken from an older nixpkgs revision (see ./nixpkgs-pins.nix
#      for why the expression rather than the package);
#   2. versions written out by hand, because no revision ever had them;
#   3. packages nixpkgs has never carried at all.

let
  pins = import ./nixpkgs-pins.nix;

  # Shorthand for "call that revision's expression with today's dependencies".
  from =
    pin: name: pyfinal:
    pyfinal.callPackage "${pin}/pkgs/development/python-modules/${name}" { };
in

pyfinal: pyprev: {

  # --- 1. taken from older nixpkgs revisions --------------------------------

  # nomad-lab: httpx>=0.23.3,<0.28 — "breaking change in 0.28 breaks keycloak
  # compatibility".  nixpkgs has 0.28.1.
  #
  # The one fix on top of 24.11's expression: nixpkgs turned pytestFlagsArray
  # from a deprecation warning into a hard error after that branch
  # (mk-python-derivation.nix rejects the attribute unless it is null or []),
  # so the flags have to be moved to its replacement.
  # Six of 0.27.2's own tests fail, in three groups, and none of them is httpx
  # misbehaving — each is a 2024 test meeting a 2026 dependency:
  #
  #   * the three `*_decode_text_using_*` cases build French text, encode it as
  #     ISO-8859-1, and assert that `chardet.detect` says "ISO-8859-1".  chardet
  #     is 6.0.0 here and answers "WINDOWS-1252".  The test's own fixture is
  #     named `cp1252_but_no_content_type`, so chardet 6 is arguably right and
  #     the older answer was the sloppy one; cp1252 is a superset of latin-1 and
  #     both decode this text identically — the very next assertion,
  #     `response.text == text`, passes.
  #   * the two `test_logging_*` cases assert `caplog.record_tuples == [one
  #     httpx record]`, an exact match on everything captured.  uvicorn is
  #     0.51.0 and its access logger now lands in the same capture, so the list
  #     has extra `uvicorn.access` entries at the front.  That is httpx's test
  #     isolation, not its logging.
  #
  # The third group is fixed rather than deselected.  `test_write_timeout[trio]`
  # dies on a ResourceWarning — trio 0.33 warns when an async generator is
  # collected unexhausted, which is exactly what a *write timeout* leaves
  # behind, so the warning is the scenario working.  httpx's pyproject sets
  # `filterwarnings = ["error"]`, so it raises; raising during GC makes it
  # unraisable; pytest 9 escalates unraisables to failures.  Suppressing
  # ResourceWarning cuts that chain at the start and keeps the timeout test
  # running, which deselecting `[trio]` would not.  Command-line -W beats the
  # ini filter (pytest applies ini first, cmdline second), which is the same
  # mechanism the two -W flags below it already rely on.
  #
  # pytestFlagsArray -> pytestFlags: nixpkgs turned the former from a
  # deprecation warning into a hard error after 24.11 (mk-python-derivation.nix
  # rejects the attribute unless it is null or []).
  #
  # disabledTestPaths is appended to, not replaced: 24.11 already lists
  # tests/test_main.py there.  Entries containing "::" become --deselect, which
  # is exact; `disabledTests` is -k and would collide with the -k that
  # expression's own `disabledTests` already produces, silently dropping its
  # three network-dependent deselections.
  httpx = (from pins.nixpkgs-2411 "httpx" pyfinal).overridePythonAttrs (old: {
    pytestFlagsArray = null;
    pytestFlags = old.pytestFlagsArray ++ [
      "-W"
      "ignore::ResourceWarning"
    ];
    disabledTestPaths = old.disabledTestPaths ++ [
      # chardet 6 reports WINDOWS-1252 where chardet 5 reported ISO-8859-1.
      "tests/client/test_client.py::test_client_decode_text_using_autodetect"
      "tests/client/test_client.py::test_client_decode_text_using_explicit_encoding"
      "tests/models/test_responses.py::test_response_decode_text_using_autodetect"
      # uvicorn 0.51's access log shares caplog with httpx's own logger.
      "tests/test_utils.py::test_logging_request"
      "tests/test_utils.py::test_logging_redirect_chain"
    ];
  });

  # nomad-lab: plotly<6 — "version 6.0.0 not fully compatible with our GUI".
  # nixpkgs has 6.8.0.
  plotly = from pins.nixpkgs-2411 "plotly" pyfinal;

  # nomad-lab: beautifulsoup4>=4,<=4.12.3 — "4.13 introduced breaking
  # changes".  nixpkgs has 4.15.0.
  #
  # Six of 4.12.3's own tests fail here, and all six are the package being two
  # years older than the things around it rather than anything wrong with it:
  #
  #   * the three `test_rejected_*` cases assert that malformed markup raises
  #     ParserRejectedMarkup.  4.12.3 raises it by catching the AssertionError
  #     that CPython's html.parser used to throw on a broken DOCTYPE or CDATA
  #     section.  CPython fixed both bugs (gh-78661, gh-81928) and backported
  #     the fixes into 3.12.x, so html.parser now accepts that input and there
  #     is nothing left to translate.  The markup parses; it simply does not
  #     raise.
  #   * the three lxml cases assert on exact serialisation — an XHTML document
  #     round-tripping byte-for-byte, a bare processing instruction, an
  #     out-of-range numeric entity.  lxml is 6.1.1 here and 4.12.3 was written
  #     against lxml 5.x, which formatted all three differently.
  #
  # Neither group touches what NOMAD uses bs4 for (the OASIS parsers scrape
  # well-formed HTML output from quantum chemistry codes), and upstream fixed
  # all six in 4.13 — the release nomad-lab's `<=4.12.3` bound exists to keep
  # out.  So they are deselected rather than chased.
  #
  # By exact node ID, because the three lxml test names are defined on shared
  # base classes in bs4/tests/__init__.py and inherited by every tree-builder
  # suite; `disabledTests` is -k, which would take out the html5lib and
  # htmlparser copies as well.  disabledTestPaths entries containing "::"
  # become --deselect, which is precise.
  beautifulsoup4 = (from pins.nixpkgs-2411 "beautifulsoup4" pyfinal).overridePythonAttrs {
    disabledTestPaths = [
      # CPython's html.parser no longer raises on these.
      "bs4/tests/test_fuzz.py::TestFuzz::test_rejected_markup"
      "bs4/tests/test_htmlparser.py::TestHTMLParserTreeBuilder::test_rejected_input"
      # lxml 6 serialises these differently than lxml 5 did.
      "bs4/tests/test_lxml.py::TestLXMLTreeBuilder::test_real_xhtml_document"
      "bs4/tests/test_lxml.py::TestLXMLTreeBuilder::test_processing_instruction"
      "bs4/tests/test_lxml.py::TestLXMLTreeBuilder::test_out_of_range_entity"
    ];
  };

  # nomad-lab: fastapi>=0.99.0,<0.137.0, upper-bounded by optimade
  # (Materials-Consortia/optimade-python-tools#2383).  nixpkgs has 0.139.0.
  fastapi = from pins.nixpkgs-fastapi136 "fastapi" pyfinal;

  # Not a NOMAD constraint — a matid one, and the reason it is scoped here
  # rather than fixed in the matid derivation.  matid's setup.py compiles its
  # extension with -std=c++11; pybind11 3.0 (what nixpkgs ships) requires
  # C++17 and fails at the first header.  24.11's expression is 2.13.6, the
  # last of the 2.x line.
  #
  # Two consequences of taking a 24.11 expression, both deliberate:
  #
  #   * `catch = null`.  That expression wants pkgs.catch, which nixpkgs has
  #     since removed ("catch has been removed. Please upgrade to catch2 or
  #     catch2_3").  catch2 is not a drop-in: pybind11 2.13's test_embed does
  #     `#include <catch.hpp>` and catch2 installs its header at
  #     catch2/catch.hpp.  catch is only ever a check input, so the tests go
  #     off with it — this is a build-time header library for matid, not
  #     something NOMAD runs, and matid's own suite (which is enabled) is what
  #     proves the pairing works.  stdenv filters the null out of the input
  #     lists.
  #
  #   * an eval warning, "pybind11: Passing `stdenv` directly to
  #     buildPythonPackage is deprecated".  That expression sets `stdenv` to
  #     work around a darwin SDK issue, and on Linux the value it picks is
  #     python.stdenv — i.e. exactly the default.  It cannot be removed
  #     (overridePythonAttrs merges its result into the old args rather than
  #     replacing them), so it is noise, not a problem.  Do not chase it.
  pybind11 =
    ((from pins.nixpkgs-2411 "pybind11" pyfinal).override { catch = null; }).overridePythonAttrs
      {
        doCheck = false;
        doInstallCheck = false;
      };

  # --- 1b. collateral damage from the httpx pin -----------------------------

  # respx is a mock transport for httpx, and it reaches this closure only as
  # test scaffolding, six links down and every link a *check* input:
  #
  #   nomad-lab -> xarray -> bokeh -> narwhals -> sqlframe -> openai -> respx
  #
  # xarray pulls bokeh in through `dask.optional-dependencies.complete`, which
  # its nativeCheckInputs splice in wholesale; narwhals check-tests against
  # sqlframe; sqlframe's `openai` extra carries respx.  Nothing NOMAD runs
  # imports any of it.  It is here because pinning httpx forces a rebuild, and
  # rebuilding a Python package means running its suite.
  #
  # Four of its tests then fail, all on one root cause.  httpx 0.28 changed how
  # a `json=` body is serialised:
  #
  #     0.27.2  json_dumps(json)                              -> {"foo": "bar"}
  #     0.28.1  json_dumps(json, separators=(",", ":"), ...)  -> {"foo":"bar"}
  #
  # respx 0.23.1 is written against 0.28, so it hard-codes the compact form:
  # two `test_json_content` cases assert Content-Length 13 and get 14, and
  # `test_callable_content` compares the body bytes directly.  The fourth,
  # `test_request_callback`, is the same thing one step removed — its callback
  # returns 202 only when `request.content == b'{"foo":"bar"}'`, so under 0.27
  # it falls through to its own 404.
  #
  # This is the scoped interpreter working as designed: the downgrade's blast
  # radius is confined to test expectations in one test-only package, instead
  # of every httpx consumer in nixpkgs.  Deselected rather than disabling the
  # whole suite, which keeps the other 311 tests honest — they are what would
  # tell us if respx stopped mocking correctly.
  #
  # `test_json_content` is deselected whole rather than by its two generated
  # parameter IDs (content0-headers0-expected_headers0 and friends): it has
  # exactly two cases and both fail, so naming the function is equivalent and
  # does not depend on pytest's ID generation staying put.
  respx = pyprev.respx.overridePythonAttrs (old: {
    disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
      "tests/test_api.py::test_json_content"
      "tests/test_api.py::test_callable_content"
      "tests/test_api.py::test_request_callback"
    ];
  });

  # --- 2. downgrades with no revision to take ------------------------------

  elasticsearch = pyfinal.callPackage ./elasticsearch-7 { };
  elasticsearch-dsl = pyfinal.callPackage ./elasticsearch-dsl-7 { };
  rdflib = pyfinal.callPackage ./rdflib-5 { };

  # --- 3. packages nixpkgs does not have -----------------------------------

  beanie = pyfinal.callPackage ./beanie { };
  fastapi-cache2 = pyfinal.callPackage ./fastapi-cache2 { };
  h5grove = pyfinal.callPackage ./h5grove { };
  lazy-model = pyfinal.callPackage ./lazy-model { };
  matid = pyfinal.callPackage ./matid { };
  molid = pyfinal.callPackage ./molid { };
  msglc = pyfinal.callPackage ./msglc { };
  optimade = pyfinal.callPackage ./optimade { };
  rfc3161ng = pyfinal.callPackage ./rfc3161ng { };

  # nomad-lab pins these two at ==0.63b1, which nixpkgs never carried; they
  # follow nixpkgs' 0.64b0 instead and the pin is relaxed.  See either
  # derivation's header for why that is safe.
  opentelemetry-instrumentation-pymongo =
    pyfinal.callPackage ./opentelemetry-instrumentation-pymongo
      { };
  opentelemetry-instrumentation-elasticsearch =
    pyfinal.callPackage ./opentelemetry-instrumentation-elasticsearch
      { };

  # --- NOMAD itself and its parser plugins ---------------------------------

  nomad-lab = pyfinal.callPackage ./nomad-lab { };
}
