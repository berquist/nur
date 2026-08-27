{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "archive-path";
  version = "0.4.2";
  pyproject = true;

  # The version comes from wc/aiida-core/uv.lock, which is upstream's own
  # resolution of `archive-path~=0.4.2`.  That is the authority for what AiiDA
  # is actually tested against; do not bump past the compatible-release bound in
  # aiida-core's pyproject.toml without checking there first.
  #
  # fetchFromGitHub rather than fetchPypi, though, because the sdist carries no
  # tests/ directory: with fetchPypi the pytestCheckPhase collected zero items
  # and reported success.  The v0.4.2 tag is the same tree plus tests/test_basic.py
  # and tests/test_glob.py.  Same reason as ../upf-to-json, which has the same
  # problem for a different upstream reason.
  src = fetchFromGitHub {
    owner = "aiidateam";
    repo = "archive-path";
    tag = "v${version}";
    hash = "sha256-wQ+T9XwuDZdZYWNW5yxwOLF2abRXuFa5/7nuHJrtDPs=";
  };

  build-system = [ flit-core ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "archive_path" ];

  meta = {
    description = "Read/write file paths within zip and tar archives";
    homepage = "https://github.com/aiidateam/archive-path";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
