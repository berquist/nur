{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  deprecation,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "pytray";
  version = "0.3.4";
  pyproject = true;

  # Pulled in only by kiwipy's `rmq` extra, which aiida-core requires.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-VfmoWNpPTrmxf1+M062ETw2NRafJMulAvCjE7x2knLw=";
  };

  build-system = [ setuptools ];

  dependencies = [ deprecation ];

  nativeCheckInputs = [ pytestCheckHook ];

  # A race, not a bug this package can fix.  The test submits a coroutine to a
  # loop running in *another* thread with `asyncio.run_coroutine_threadsafe`,
  # then immediately calls `.cancel()` on the concurrent future it gets back and
  # asserts the coroutine never ran.  `Future.cancel()` only succeeds while the
  # task is still pending, so the assertion holds only if the submitting thread
  # reaches `.cancel()` before the loop thread wakes on the self-pipe and runs
  # the callback.  That window is under a microsecond: sleeping 1e-6 between the
  # two lines flips the test from 0/100 failures to 94/100.
  #
  # So it passes on an idle machine and loses under contention.  It has never
  # failed here, and it failed on a four-core GitHub runner midway through a
  # `--keep-going` build of the whole of ci.nix.  There is nothing to retry
  # against and no dependency to supply — upstream is asserting a scheduling
  # order asyncio does not promise.
  disabledTests = [ "test_task_cancel" ];

  pythonImportsCheck = [ "pytray" ];

  meta = {
    description = "A python tray of util functions";
    homepage = "https://github.com/muhrin/pytray";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
