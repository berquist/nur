# rdflib, pinned to 5.0.0.
#
# nomad-lab declares `rdflib==5` — an exact pin, not a floor — because rdflib 6
# changed what `DCT.dataset` resolves to, and NOMAD's DCAT export
# (nomad/app/dcat/) emits that term.  nixpkgs ships 7.5.0 and the only revision
# that ever carried 5.0.0 is nixos-21.05, whose expression is python2-era and
# will not callPackage against a modern package set.  So this one is written
# out by hand.
#
# 5.0.0 is from 2020 and this is the oldest thing in the NOMAD closure.  Two
# things that would break it on Python 3.13 turn out not to:
#
#   * the collections -> collections.abc migration is already guarded upstream
#     (rdflib/compat.py tries collections.abc first), and
#   * the one `import cgi` — a module removed in 3.13 — sits in
#     rdflib/tools/rdf2dot.py, a CLI entry point the library core never
#     imports.  Hence the deliberately narrow pythonImportsCheck below.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  isodate,
  pyparsing,
  six,
}:

buildPythonPackage rec {
  pname = "rdflib";
  version = "5.0.0";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-eBSd1J04Xv7Ds6371hyHr68SgcMNP8rxsyOzT2A/sVU=";
  };

  build-system = [ setuptools ];

  dependencies = [
    isodate
    pyparsing
    six
  ];

  # setup.py sets `test_suite = "nose.collector"` and the whole suite under
  # test/ is written against nose, which was dropped from nixpkgs (it has not
  # worked since Python 3.10).  There is no runner to point pytest at without
  # rewriting upstream's suite, so the check is the import test below plus the
  # DCAT assertions in the oasis-minimal VM test.
  doCheck = false;

  # Deliberately excludes rdflib.tools.* — see the header.
  pythonImportsCheck = [
    "rdflib"
    "rdflib.graph"
    "rdflib.namespace"
    "rdflib.plugins.serializers.turtle"
  ];

  meta = {
    description = "Python library for working with RDF, pinned to the 5.x series";
    homepage = "https://github.com/RDFLib/rdflib";
    license = lib.licenses.bsd3;
    maintainers = [ lib.maintainers.berquist ];
  };
}
