{
  lib,
  buildPythonApplication,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,

  # runtime tools, not Python modules — see makeWrapperArgs below
  diffutils,
  file,

  # build-system
  setuptools,

  # dependencies (pyproject.toml [project].dependencies)
  distro,
  docopt-ng,
  jinja2,
  packaging,
  python-magic,
  requests,
  ruamel-yaml,
  tomli-w,

  # tests
  pytestCheckHook,
}:

buildPythonApplication rec {
  pname = "dotdrop";
  version = "1.16.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "deadc0de6";
    repo = "dotdrop";
    tag = "v${version}";
    hash = "sha256-kgy4ESUEQnlB5lfyUIuvxaqLqiJ4+Qq1T5JwCcqLo+E=";
  };

  build-system = [ setuptools ];

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  # dotdrop shells out to two Unix tools and refuses to run without them:
  #
  #   utils.dependencies_met(), called from dotdrop.py's main() on *every*
  #   invocation, does shutil.which('file') and raises UnmetDependency if it
  #   comes back empty;
  #
  #   Settings validates config's `diff_command`, which defaults to
  #   "diff -r -u {0} {1}", through utils.is_bin_in_path() — so loading any
  #   config at all needs diff.
  #
  # Neither is a Python dependency, so nothing in pyproject.toml pulls them in
  # and the upstream test suites never notice: they run in a dev environment
  # where both are already on PATH.  On a minimal system dotdrop would abort at
  # startup.
  #
  # --suffix, not --prefix: diff_command is user-configurable and `file` is the
  # sort of thing a user may deliberately override, so these are a fallback
  # rather than an override of the caller's PATH.
  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [
      diffutils
      file
    ])
  ];

  # `tomli` is a dependency only below Python 3.11; the environment marker keeps
  # it out on every interpreter this is built against, so it is not listed here.
  dependencies = [
    distro
    docopt-ng
    jinja2
    packaging
    python-magic
    requests
    ruamel-yaml
    tomli-w
  ];

  # `file` for the same reason as makeWrapperArgs — the wrapper does not exist
  # yet at checkPhase, so the tests need it on PATH in their own right.
  # diffutils is already in stdenv.
  nativeCheckInputs = [
    pytestCheckHook
    file
  ];

  # tests/ writes real dotfiles into $HOME and creates ~/.config — see
  # test_import.test_import and the fold_config setup in test_compare,
  # test_listings and test_update.  The default $HOME (/homeless-shelter) does
  # not exist, so they fail at setup without this.
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # Only the pytest suite under tests/ runs here.  tests-ng/ is a separate
  # 154-script shell suite that drives the CLI end to end; it is run against the
  # *installed* binary by the dotdrop-roundtrip test instead (see ../../tests),
  # which is what makes it worth anything as a packaging check.
  pytestFlags = [ "tests" ];

  pythonImportsCheck = [
    "dotdrop"
    "dotdrop.dotdrop"
    "dotdrop.importer"
    "dotdrop.installer"
  ];

  postInstall = ''
    installManPage manpage/dotdrop.1
    installShellCompletion \
      --bash --name dotdrop.bash completion/dotdrop-completion.bash \
      --zsh --name _dotdrop completion/_dotdrop-completion.zsh \
      --fish --name dotdrop.fish completion/dotdrop.fish
  '';

  meta = {
    description = "Save your dotfiles once, deploy them everywhere";
    homepage = "https://github.com/deadc0de6/dotdrop";
    changelog = "https://github.com/deadc0de6/dotdrop/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "dotdrop";
  };
}
