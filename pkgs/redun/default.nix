{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  uv-build,

  # dependencies
  aiobotocore,
  aiohttp,
  alembic,
  boto3,
  botocore,
  python-dateutil,
  pyyaml,
  requests,
  rich,
  s3fs,
  sqlalchemy,
  textual,
}:

# redun — a workflow engine ("yet another"), one of quacc's engine adapters
# (`quacc[redun]`).
buildPythonPackage {
  pname = "redun";
  version = "0.46.0-unstable-2026-07-09";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "insitro";
    repo = "redun";
    rev = "49a299b223bc345b999aaa40daa6876f105089e1";
    hash = "sha256-X6SwOlYhRWUvOVsUKljOW99w1aNdB6/DnwC5PoniKcY=";
  };

  # `uv_build < 0.10` in the build requirements; nixpkgs carries 0.11, and
  # pypaBuildPhase checks the pin against what is installed with `--no-isolation`.
  # uv-build is forward-compatible over this range.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'uv_build>=0.9.22,<0.10.0' 'uv_build'
  '';

  build-system = [ uv-build ];

  # fancycompleter is a readline tab-completer used only by `redun console`
  # (the TUI in `redun/console/screens.py`); it is not in nixpkgs and the core
  # package does not import it.
  pythonRemoveDeps = [ "fancycompleter" ];

  dependencies = [
    aiobotocore
    aiohttp
    alembic
    boto3
    botocore
    python-dateutil
    pyyaml
    requests
    rich
    s3fs
    sqlalchemy
    textual
  ];

  # The suite is not run.  redun's tests exercise its AWS Batch / Glue / k8s /
  # Docker executors against mocked or local backends, and `redun console`,
  # which needs the removed `fancycompleter`.  `pythonImportsCheck` covers the
  # scheduler and the local executor.
  doCheck = false;

  pythonImportsCheck = [
    "redun"
    "redun.scheduler"
    "redun.executors.local"
  ];

  meta = {
    description = "Workflow engine for data science pipelines";
    homepage = "https://github.com/insitro/redun";
    license = lib.licenses.asl20;
    mainProgram = "redun";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
