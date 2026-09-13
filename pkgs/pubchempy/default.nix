{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # optional-dependencies
  certifi,
  pandas,
}:

buildPythonPackage (finalAttrs: {
  pname = "pubchempy";
  version = "1.0.5";
  pyproject = true;
  __structuredAttrs = true;

  # The distribution is `PubChemPy`; the import name is `pubchempy`, and the
  # whole library is one module of that name at the top of the tree.
  src = fetchFromGitHub {
    owner = "mcs07";
    repo = "PubChemPy";
    rev = "v${finalAttrs.version}";
    hash = "sha256-/gMvn222LXs2iRGo3f64oU8oQLWCd3gPmyFghryzmIE=";
  };

  build-system = [ setuptools ];

  # Genuinely none — it is a wrapper over PubChem's PUG REST API built on
  # urllib, and both extras are conveniences rather than requirements.
  dependencies = [ ];

  optional-dependencies = {
    pandas = [ pandas ];
    ssl = [ certifi ];
  };

  # Every one of the thirteen test modules talks to
  # https://pubchem.ncbi.nlm.nih.gov over the network, and there is no
  # cassette, mock or fixture anywhere in the suite to stand in for it — the
  # only thing tests/conftest.py contains is a commented-out fixture that
  # sleeps a second between tests to stay under PubChem's rate limit, which is
  # about as clear a statement as upstream could make about what the suite is.
  #
  # So this is not the usual "the sdist ships no tests" case that ../mdanalysis
  # documents, and it cannot be narrowed to a disabledTestPaths list either:
  # nothing is left once the network goes.  A build sandbox has no network by
  # design and should not get one for this.
  doCheck = false;

  # Which leaves this as the only thing between a typo and a green build.  It
  # still runs: pythonImportsCheckHook appends its phase to preDistPhases
  # unconditionally, so `doCheck = false` does not switch it off — only
  # `dontUsePythonImportsCheck` would.  One module means there is nothing
  # deeper to name, but importing it does execute the whole module body, which
  # is where the urllib imports and the property table the API is generated
  # from live.
  pythonImportsCheck = [ "pubchempy" ];

  meta = {
    description = "Simple Python wrapper around the PubChem PUG REST API";
    homepage = "https://github.com/mcs07/PubChemPy";
    changelog = "https://github.com/mcs07/PubChemPy/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
