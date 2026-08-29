{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  aiida-core,

  # tests
  pytestCheckHook,
  pytest-regressions,
  pytest-datadir,
  pgtest,
  postgresql,
  coreutils,
  stdenv,
  glibcLocalesUtf8,
}:

buildPythonPackage rec {
  pname = "aiida-wannier90";
  version = "2.2.0";
  pyproject = true;

  # Not fetchPypi: `[tool.flit.sdist] exclude` drops `tests/`, and a check phase
  # that collects nothing passes.  See ../../AGENTS.md.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "aiida-wannier90";
    tag = "v${version}";
    hash = "sha256-cv8NkjChvQmXiBAAErZeZBC2aevTzl8yOK010S0R9MA=";
  };

  build-system = [ flit-core ];

  # See ../aiida-orca/default.nix: our aiida-core is a pre-release, which does
  # not satisfy `aiida-core>=2.0,<3` under PEP 440 without an opt-in.
  pythonRelaxDeps = [ "aiida-core" ];

  dependencies = [ aiida-core ];

  # `/bin/true` is what tests/conftest.py hands `Code(remote_computer_exec=...)`,
  # and a Nix build sandbox has only /bin/sh.  ../aiida-orca/default.nix has the
  # long form of why an absent executable does not surface as "no such file".
  postPatch = ''
    substituteInPlace tests/conftest.py \
      --replace-fail '"/bin/true"' '"${coreutils}/bin/true"'
  '';

  preCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${glibcLocalesUtf8}/lib/locale/locale-archive"
  '';

  nativeCheckInputs = [
    pytestCheckHook

    # file_regression over the generated .win input files, and `shared_datadir`
    # — a pytest-datadir fixture, not a pytest-regressions one, which is why
    # both are here.
    pytest-regressions
    pytest-datadir

    # tests/conftest.py names `aiida.manage.tests.pytest_fixtures`, the
    # deprecated module, whose profile is a real PostgreSQL one.  See ../pgtest
    # for why postgresql is listed alongside, and ../aiida-core/default.nix for
    # what that module needs patched to work without a broker.
    pgtest
    postgresql
  ];

  # See ../aiida-core/default.nix for why this is preBuild and not preCheck.
  preBuild = ''
    export HOME="$(mktemp -d)"
    export AIIDA_PATH="$HOME"
  '';

  # No wannier90 binary is needed.  Nothing in the suite calls `engine.run`: the
  # calculation tests assert on the input file written into a sandbox folder and
  # the parser tests replay the stored outputs under tests/parsers/.
  pythonImportsCheck = [
    "aiida_wannier90"
    "aiida_wannier90.calculations"
    "aiida_wannier90.parsers"
    "aiida_wannier90.workflows"
  ];

  meta = {
    description = "AiiDA plugin for the Wannier90 maximally-localised Wannier functions code";
    homepage = "https://github.com/aiidateam/aiida-wannier90";
    changelog = "https://github.com/aiidateam/aiida-wannier90/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
