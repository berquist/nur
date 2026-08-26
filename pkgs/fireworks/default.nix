{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  flask,
  flask-paginate,
  gunicorn,
  jinja2,
  monty,
  numpy,
  pymongo,
  python-dateutil,
  ruamel-yaml,
  tabulate,
  tqdm,

  # tests
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "fireworks";
  # 2.1.4, not the v2.0.2 that `git describe` reports for this commit: the tag
  # is behind, and setup.py here declares `version="2.1.4"`.  atomate2 and
  # jobflow both pin `FireWorks==2.1.4`, so the source is the one to believe.
  version = "2.1.4-unstable-2026-08-11";
  pyproject = true;

  # The distribution is `FireWorks`; the import name is `fireworks`.
  src = fetchFromGitHub {
    owner = "materialsproject";
    repo = "fireworks";
    rev = "71686559d2a407c976cc56b6fa3c648819ee8fe3";
    hash = "sha256-J2fGV35MWsbgwoSyS2W7YBewFELFqZR6t5WyUS/kVn8=";
  };

  build-system = [ setuptools ];

  dependencies = [
    flask
    flask-paginate
    gunicorn
    jinja2
    monty
    # Not declared by upstream, and needed anyway — `import fireworks` fails
    # without it:
    #
    #   File ".../fireworks/fw_config.py", line 11, in <module>
    #     from monty.serialization import dumpfn, loadfn
    #   File ".../monty/json.py", line 24, in <module>
    #     import numpy as np
    #   ModuleNotFoundError: No module named 'numpy'
    #
    # monty imports numpy unconditionally at the top of json.py, but nixpkgs
    # lists numpy only in monty's `optional-dependencies`, never in
    # `dependencies`.  So every monty dependant that reaches serialization has
    # to carry numpy itself.  That is a latent nixpkgs bug rather than ours;
    # repairing monty here instead would change it for every consumer of this
    # overlay, which is a bigger blast radius than the problem deserves.
    numpy
    pymongo
    python-dateutil
    ruamel-yaml
    tabulate
    tqdm
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  # No MongoDB is provided, and unlike most of this tree that is not a gap.
  # FireWorks' LaunchPad tests live in exactly three modules, and all three
  # check for a server on localhost:27017 and raise unittest.SkipTest when there
  # is none.  Two of them — mongo_tests.py and multiprocessing_tests.py — are
  # not even collectible: pytest's default python_files matches neither, so they
  # never run under pytestCheckHook whatever the environment.  Only
  # test_deserialization.py both collects and skips.
  #
  # That leaves the other twenty-three modules — serializers, queue adapters,
  # firetasks, templates — running for real against no database at all.
  #
  # Several of those import `fw_tutorials.*`, which is a second top-level
  # package in this repository rather than a test fixture.  setup.py's bare
  # find_packages() picks it up (it carries four __init__.py files), so it is
  # installed alongside `fireworks` and the imports resolve.

  pythonImportsCheck = [
    "fireworks"
    "fireworks.core.firework"
    "fireworks.core.launchpad"
  ];

  meta = {
    description = "Workflow software for running high-throughput calculation workflows";
    homepage = "https://github.com/materialsproject/fireworks";
    changelog = "https://github.com/materialsproject/fireworks/blob/main/CHANGES.txt";
    license = lib.licenses.bsd3;
    # Four console scripts, none of them named after the package: lpad, mlaunch,
    # qlaunch and rlaunch.  lib.getExe would otherwise fall back to "fireworks"
    # and produce a path that does not exist.
    mainProgram = "lpad";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
