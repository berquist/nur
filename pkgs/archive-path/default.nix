{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  flit-core,

  # tests
  # pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "archive-path";
  version = "0.4.2";
  pyproject = true;

  # Version and hash both come from wc/aiida-core/uv.lock, which is upstream's
  # own resolution of `archive-path~=0.4.2`.  That is the authority for what
  # AiiDA is actually tested against; do not bump past the compatible-release
  # bound in aiida-core's pyproject.toml without checking there first.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-dSeQA+qYak9nSOKZunTZXnStdfG9OuAtNcElx0ljOlE=";
  };

  build-system = [ flit-core ];

  # nativeCheckInputs = [ pytestCheckHook ];
  # We skip simply because there are no tests, at least with the pytest
  # default collection arguments.
  doCheck = false;

  pythonImportsCheck = [ "archive_path" ];

  meta = {
    description = "Read/write file paths within zip and tar archives";
    homepage = "https://github.com/aiidateam/archive-path";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
