{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  flit-core,

  # dependencies
  click,
  cloudpickle,
  graphviz,
  node-graph-widget,
  numpy,
  pydantic,
  pyyaml,
  rdflib,
  scipy,
  typing-extensions,
  wrapt,

  # tests
  pytestCheckHook,
  pytest-asyncio,
}:

buildPythonPackage rec {
  pname = "node-graph";
  version = "0.6.5";
  pyproject = true;

  # The tag, and *not* the one commit past it.  That commit is
  # `8d85e61 Add GraphTaskHandle (#150)`, whose own message says "`build` is
  # now graph-only by handle type": it moves `build` off the base handle and
  # onto a new `GraphTaskHandle` subclass.  ../aiida-workgraph calls
  # `.build(...)` on ordinary task handles — in its own `task.py` and
  # `decorator.py`, not merely in its tests — so with that commit in place
  # twenty of its tests fail with
  #
  #   AttributeError: 'TaskHandle' object has no attribute 'build'
  #
  # Both aiida-workgraph and ../aiida-pythonjob ask for `node-graph~=0.6.5`,
  # which is the release, so the release is what they get.  There is no newer
  # 0.6.x to move to; the API those two are written against exists only at the
  # tag.
  src = fetchFromGitHub {
    owner = "scinode";
    repo = "node-graph";
    tag = "v${version}";
    hash = "sha256-36ZsR6o3fN5VPqOJDMwHh2f45kvcEE0XEYJqir+plrU=";
  };

  build-system = [ flit-core ];

  # node-graph-widget is a hard runtime dependency, not an extra:
  # src/node_graph/task.py does `from node_graph_widget import NodeGraphWidget`
  # at module scope, and mixins.py imports it again inside two methods.
  dependencies = [
    click
    cloudpickle
    graphviz
    node-graph-widget
    numpy
    pydantic
    pyyaml
    rdflib
    scipy
    typing-extensions
    wrapt
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
  ];

  pythonImportsCheck = [
    "node_graph"
    "node_graph.task"
    "node_graph.socket_spec"
  ];

  meta = {
    description = "Library for building and running node-based workflow graphs";
    homepage = "https://github.com/scinode/node-graph";
    license = lib.licenses.mit;
    mainProgram = "node-graph";
    maintainers = with lib.maintainers; [ berquist ];
  };
}
