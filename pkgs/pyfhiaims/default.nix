{
  lib,
  buildPythonPackage,
  fetchFromGitLab,

  # build-system
  setuptools,
  versioningit,

  # dependencies
  monty,
  numpy,

  # tests
  pytestCheckHook,
  pyyaml,
}:

# pyfhiaims — FHI-aims' own Python package: readers and writers for `control.in`
# and `geometry.in`, the species-defaults tree, and a parser for the program's
# standard output.  It is here for one dependant, ../pymatgen-io-aims, which is
# in turn here for ../atomate2's `tests/aims`; see "Deferred packaging" in
# ../../AGENTS.md.  Internal, and not re-exported.
buildPythonPackage (finalAttrs: {
  pname = "pyfhiaims";
  version = "1.1.1-unstable-2026-09-10";
  pyproject = true;
  __structuredAttrs = true;

  # GitLab, like ../hiphive, ../trainstation and ../ase-db-backends.  The
  # repository has **no tags at all** — not one, at any point in its history —
  # so this is `-unstable-` by necessity rather than by choice of a commit past
  # a release.  `1.1.1` is what `pyfhiaims/__init__.py` carries, and it is the
  # number that matters: ../pymatgen-io-aims requires `pyfhiaims>=1.1.0`.
  src = fetchFromGitLab {
    owner = "FHI-aims-club";
    repo = "pyfhiaims";
    rev = "0b5799210c18dd1148c8e827c23d4234bcb3c064";
    hash = "sha256-qToKvI9B1h7X0rW5PNl1fOQ1CxJm6kwqVThMbZ+dSqg=";
  };

  # versioningit's `method = "git"` against an archive with no repository.  The
  # same trap as ../atomate2 and ../qtoolkit, and the same fix — a top-level
  # `default-version`, which is what versioningit falls back to for any error
  # during version calculation.  Upstream declares only the `vcs` sub-table.
  #
  # `default-tag = "0.0.1"` in that sub-table is not a substitute: it applies
  # when the repository exists but has no tag reachable, which is a different
  # failure from having no repository at all.  Taking it would also produce a
  # version *below* the `>=1.1.0` floor ../pymatgen-io-aims declares, so the
  # dependant would refuse to build against it.
  #
  # Only the part of `version` before the first dash goes in; `-unstable-` is
  # not PEP 440.
  #
  # The `versioningit ~= 1.0` cap is a *build-system* requirement, which is
  # why it is rewritten here rather than through `pythonRelaxDeps`: that hook
  # only reaches `[project] dependencies` and its extras, so a `requires` pin
  # is left to fail the build with
  #
  #   ERROR Unmet dependencies: versioningit~=1.0
  #           wanted: ~=1.0
  #           found: 3.3.0
  #
  # ../aiida-gromacs rewrites a flit_core pin for the same reason.  Dropping
  # the bound rather than widening it: the only versioningit feature this
  # project uses is the `vcs` method, and the `default-version` the line above
  # adds is the documented fallback in 1.x, 2.x and 3.x alike.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"versioningit ~= 1.0"' '"versioningit"' \
      --replace-fail \
        '[tool.versioningit.vcs]' \
        '[tool.versioningit]
    default-version = "${lib.head (lib.splitString "-" finalAttrs.version)}"

    [tool.versioningit.vcs]'
  '';

  # Upstream's `requires` also names numpy and wheel.  wheel is vestigial —
  # setuptools has supplied its own since PEP 517 — and numpy is a runtime
  # dependency listed twice, so it is already on the path the build sees.
  build-system = [
    setuptools
    versioningit
  ];

  dependencies = [
    monty
    numpy
  ];

  # pyyaml for `tests/conftest.py`, which reads the parser's check files from
  # YAML.  It is in upstream's `tests` extra rather than its dependencies, and
  # nothing under `pyfhiaims/` imports it.
  nativeCheckInputs = [
    pytestCheckHook
    pyyaml
  ];

  # `tests/` is a package — it has an `__init__.py`, and the modules under it
  # do `from tests.utils import ...` — so the suite has to run from the source
  # root rather than from `tests/`.  That is the default here, and the reason
  # this is a note instead of a `preCheck`.
  #
  # It also means setuptools installs it: `[tool.setuptools.packages.find]`
  # sets `where = ["."]` with no `include`, so `tests` lands in the wheel
  # beside `pyfhiaims`.  nixpkgs' `pythonRemoveTestsDir` hook takes it out of
  # `$out` again, which is the only reason this does not collide with every
  # other package that ships a top-level `tests`.
  pythonImportsCheck = [
    "pyfhiaims"
    "pyfhiaims.control.control"
    "pyfhiaims.geometry.geometry"
    "pyfhiaims.outputs.stdout"
    "pyfhiaims.species_defaults.species"
  ];

  meta = {
    description = "FHI-aims' own Python package for its input and output files";
    homepage = "https://gitlab.com/FHI-aims-club/pyfhiaims";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
})
