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
  numpy,

  # tests
  pytestCheckHook,
  pytest-mock,
  pydantic,
  ruamel-yaml,
  procps,
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
    # numpy is not upstream's, and not ours either — it belongs to monty, which
    # imports it unconditionally at the top of json.py.  On nixos-26.05 that is
    # monty 2025.3.3, whose nixpkgs derivation propagates only msgpack and
    # ruamel-yaml, so anything reaching `from monty.json import MSONable` dies:
    #
    #   .../monty/json.py:24: in <module>
    #       import numpy as np
    #   E   ModuleNotFoundError: No module named 'numpy'
    #
    # Both unstable legs carry monty 2026.7.16, where nixpkgs *has* fixed this
    # and numpy is propagated, so listing it here is a no-op there rather than
    # a second copy.  Beside monty rather than in `dependencies` because that
    # is the only thing that drags monty in — qtoolkit itself imports it lazily,
    # inside QTKEnum._validate_monty, and a consumer without this extra never
    # reaches the import at all.
    #
    # Delete it with the `monty` binding in ../../overlays/default.nix, which
    # is version-guarded against the same 26.05/unstable split and carries the
    # note about when 26.05 leaves ../../Justfile's `channels`.
    msonable = [
      monty
      numpy
    ];
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
  # procps for `ps`.  ShellIO is qtoolkit's own scheduler-less backend — it
  # launches a job with `nohup bash …&` and then lists it by building a literal
  # ["ps", …] argv in _get_jobs_list_cmd — so TestShellIO::test_get_jobs_list
  # submits a real sleep and asks for it back.  Without it the build sees
  #
  #   CommandFailedError: command ps failed: stdout: .
  #     stderr: …/bin/sh: line 1: ps: command not found
  #
  # A check input rather than a runtime dependency, and rewriting that "ps" to
  # a store path would be wrong rather than merely heavy: ShellIO is also what
  # runs over a fabric connection to another machine, where an absolute path
  # into *this* closure names nothing.  It is the same call qtoolkit makes for
  # qsub, sbatch and qstat, all of which it likewise leaves to PATH.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-mock
    pydantic
    ruamel-yaml
    procps
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
