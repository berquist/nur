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

  # NumPy 2.5 deprecated assigning to an array's `.dtype`, which mrcfile does
  # at eight places to reinterpret a header buffer in another byte order or as
  # an extended-header type — five in the library, three more in the tests.
  # The library still works — it is a DeprecationWarning, not a removal — but
  # the suite does not: the base class in tests/test_mrcobject.py calls
  # `warnings.simplefilter("error")`, and a further sixteen tests count or
  # match the warnings a call emits.  One extra warning per operation turned
  # into 366 failures out of 861.
  #
  # Suppressing it at the call sites keeps the assignment itself unchanged,
  # which matters: upstream's own comment above each of the library ones
  # records that neither `view` nor `astype` does what is needed there, so
  # rewriting them would be a behaviour change rather than a modernisation.
  # Pinning numpy 2.4 for this package alone is the other obvious route and is
  # worse — ../mdanalysis and ../griddataformats carry compiled extensions
  # built against 2.5, so it would put two incompatible NumPys in one closure.
  #
  # The three test sites need the same treatment for a second reason beyond
  # the promoted warning: one of them sits inside a `catch_warnings(record=True)`
  # that asserts it recorded exactly one message.  A nested suppressing context
  # keeps the deprecation out of that recorder, which is what turns `assert
  # 2 == 1` back into a pass.
  #
  # The pattern has to allow a dotted receiver — the library writes
  # `header.dtype = ...` but the tests write `mrc.extended_header.dtype = ...`.
  # It matches assignment only, never the `.dtype.kind ==` comparisons beside
  # it, because those lines do not start with the receiver.
  #
  # Drop this once upstream adopts whatever NumPy settles on as the
  # replacement; the tracking comments are already in the source.
  postPatch = ''
    for f in src/mrcfile/mrcobject.py src/mrcfile/mrcinterpreter.py tests/test_mrcfile.py; do
      sed -i -E 's|^([[:space:]]*)([A-Za-z_][A-Za-z_0-9.]*\.dtype = .*)$|\1with warnings.catch_warnings():\n\1    warnings.simplefilter("ignore", DeprecationWarning)\n\1    \2|' "$f"
    done
  '';

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
