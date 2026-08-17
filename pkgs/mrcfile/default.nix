{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  numpy,

  # tests
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "mrcfile";
  version = "1.5.4-unstable-2026-03-02";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ccpem";
    repo = "mrcfile";
    rev = "a2a8c6b569a57b7f18b023b5056fa7a14f2f99c2";
    hash = "sha256-///ttxWMEZWSw+KsESd7cqUnLtg9Z+o/RK4kwu5eiN4=";
  };

  build-system = [ setuptools ];

  dependencies = [ numpy ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "mrcfile" ];

  meta = {
    description = "MRC file I/O library, for cryo-EM and tomography density maps";
    homepage = "https://github.com/ccpem/mrcfile";
    changelog = "https://github.com/ccpem/mrcfile/blob/master/CHANGELOG.txt";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
