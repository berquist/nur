{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  poetry-core,

  # dependencies
  click,
  numpy,
  regex,

  # tests
  pytestCheckHook,
  pytest-console-scripts,
}:

buildPythonPackage rec {
  pname = "cp2k-output-tools";
  version = "0.5.0";
  pyproject = true;

  # aiida-cp2k depends on this unbounded, so any recent release will do.
  #
  # fetchPypi does not work here at all: PyPI serves no sdist for 0.5.0 under
  # either spelling, so every mirror 404s.  Upstream publishes wheels only.
  # The tag carries the tests the sdist would not have had anyway.
  src = fetchFromGitHub {
    owner = "cp2k";
    repo = "cp2k-output-tools";
    tag = "v${version}";
    hash = "sha256-IeAaBAlpvNu9CSMjFSmik7dR+m2+YBbzjiVunadQLyA=";
  };

  build-system = [ poetry-core ];

  # Upstream still asks for the pre-1.1 backend, `poetry.masonry.api` from the
  # full `poetry` application, which nixpkgs does not expose as a Python
  # module.  poetry-core has provided the same entry points under
  # `poetry.core.masonry.api` since 1.0, so the rewrite is a rename.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["poetry>=1"]' 'requires = ["poetry-core>=1"]' \
      --replace-fail 'build-backend = "poetry.masonry.api"' \
                     'build-backend = "poetry.core.masonry.api"'
  '';

  # `regex = ">=2021.4,<2022.0"` and `numpy = "^1.19"` are both five years
  # stale; nothing in the source cares about either bound.
  pythonRelaxDeps = [
    "numpy"
    "regex"
  ];

  dependencies = [
    click
    numpy
    regex
  ];

  # Four of the eight test files drive the console scripts through the
  # `script_runner` fixture and the `script_launch_mode` mark, both of which
  # come from pytest-console-scripts — upstream's dev-dependencies list it.
  # Without it those marks are unknown and the ten tests using them error.
  nativeCheckInputs = [
    pytestCheckHook
    pytest-console-scripts
  ];

  # Those four files carry `@pytest.mark.script_launch_mode("subprocess")`, so
  # script_runner execs the console scripts as real programs instead of calling
  # their entry points in-process.  buildPythonPackage does not put $out/bin on
  # PATH for the check phase, so each one failed with FileNotFoundError on a
  # path resolved relative to the build directory.
  preCheck = ''
    export PATH="$out/bin:$PATH"
  '';

  pythonImportsCheck = [ "cp2k_output_tools" ];

  meta = {
    description = "Parsers and tools for CP2K output files";
    homepage = "https://github.com/cp2k/cp2k-output-tools";
    license = lib.licenses.mit;
    # There is no `cp2k-output-tools` executable — the four console scripts are
    # cp2kparse, cp2k_bs2csv, cp2k_pdos and xyz_restart_cleaner.  Naming the
    # package here would have made `lib.getExe` resolve to a path that does not
    # exist, which it reports only at runtime.
    mainProgram = "cp2kparse";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
