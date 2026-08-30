{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,
  versioningit,

  # optional-dependencies
  fabric,
  monty,

  # tests
  pytestCheckHook,
  pytest-mock,
  pydantic,
  ruamel-yaml,
}:

buildPythonPackage (finalAttrs: {
  pname = "qtoolkit";
  version = "0.1.7";
  pyproject = true;
  __structuredAttrs = true;

  # The v0.1.7 tag rather than HEAD, which is nine commits past it and all of
  # them documentation or dependabot noise.  jobflow-remote asks for
  # `qtoolkit >= 0.1.6`, so the tag satisfies it with a version string that
  # means something.
  src = fetchFromGitHub {
    owner = "Matgenix";
    repo = "qtoolkit";
    rev = "v${finalAttrs.version}";
    hash = "sha256-fMOo7v0/uxWw7SOiYAnRuzOhB20NYoGwpS21b+kNM84=";
  };

  # versioningit's `method = "git"` wants a repository, and fetchFromGitHub
  # gives a tarball with no .git, so the build dies in `prepareBuild` before
  # anything is compiled.  `default-tag` — which upstream does set — is not the
  # escape: it only applies when the repository exists and carries no tags.
  # The one that covers a missing repository outright is the top-level
  # `default-version`, which versioningit falls back to for *any* error during
  # version calculation (core.py:297).  Upstream declares no `[tool.versioningit]`
  # table at all, so this inserts one ahead of the `vcs` sub-table it does
  # declare — order matters in TOML, a parent table cannot follow its child.
  #
  # ../mda-xdrlib and ../qmzyme reach the same fallback by rewriting a
  # `default-version` that upstream already spells out; this is the same fix for
  # a project that does not.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${finalAttrs.version}"

    [tool.versioningit.vcs]'
  '';

  build-system = [
    setuptools
    versioningit
  ];

  # Genuinely none.  qtoolkit is a pure-stdlib wrapper over PBS/SLURM/SGE
  # command lines and their output formats; everything else it can use is an
  # extra.
  dependencies = [ ];

  optional-dependencies = {
    remote = [ fabric ];
    msonable = [ monty ];
  };

  # monty is an extra upstream, but the suite is not optional about it: the io
  # and core tests read their reference files with `monty.serialization.loadfn`
  # and check MSONable round-trips through `jsanitize`, so without it most of
  # what is left after the integration split below collects and fails.
  # ruamel-yaml comes with it for the .yaml fixtures, and upstream's own
  # `tests` extra names it separately for the same reason.
  #
  # pydantic is undeclared in every extra and needed anyway:
  # TestQEnum::test_serialization imports it directly to check that a QTKEnum
  # survives a round trip through a BaseModel.  It is guarded on monty being
  # importable but not on pydantic, so a set without it does not skip the test,
  # it fails it.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mock
    pydantic
    ruamel-yaml
  ]
  ++ finalAttrs.passthru.optional-dependencies.msonable;

  # tests/integration/ drives real queues.  Its conftest builds PBS, SLURM and
  # SGE containers through python-on-whales — a Docker client binding that
  # nixpkgs does not carry — and then submits jobs to them over SSH.  Nothing
  # about that is reachable from a build sandbox, and the twelve modules
  # outside it cover the io parsers and the local host, which is the half
  # jobflow-remote actually links against.
  disabledTestPaths = [ "tests/integration" ];

  pythonImportsCheck = [
    "qtoolkit"
    "qtoolkit.core.data_objects"
    "qtoolkit.io.slurm"
  ];

  meta = {
    description = "Python wrapper interfacing with job queues such as PBS and SLURM";
    homepage = "https://github.com/Matgenix/qtoolkit";
    changelog = "https://github.com/Matgenix/qtoolkit/blob/v${finalAttrs.version}/CHANGELOG.md";
    # pyproject.toml says only `license = { text = "modified BSD" }`, with no
    # classifier and no SPDX identifier.  LICENSE is the three-clause text.
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
