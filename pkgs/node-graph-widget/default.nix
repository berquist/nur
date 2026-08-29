{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  python,

  # build-system
  hatchling,
  hatch-jupyter-builder,

  # the esbuild bundle, built by ../node-graph-widget-js from this same source
  node-graph-widget-js,

  # dependencies
  anywidget,
}:

buildPythonPackage rec {
  pname = "node-graph-widget";
  version = "0.0.5-unstable-2025-11-27";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "scinode";
    repo = "node-graph-widget";
    rev = "171ef0579adbc28f430fdbcf5bf9ee54a425a258";
    hash = "sha256-u7kfu5bGw6044Y3x0sKFuaTYzCEi5LwSjUAn9nsOSeI=";
  };

  build-system = [
    hatchling
    hatch-jupyter-builder
  ];

  # The frontend, dropped in before hatchling runs.
  #
  # pyproject.toml wires hatch-jupyter-builder to run `npm run build` during the
  # wheel build, which a Nix builder cannot do — no network for the registry.
  # It also declares
  #
  #   skip-if-exists = ["src/node_graph_widget/static/widget.js"]
  #
  # so putting the bundle there first turns that hook into a no-op, and
  # `artifacts = ["src/node_graph_widget/static/*"]` is what gets the files into
  # the wheel despite .gitignore.  ../node-graph-widget-js is the same source
  # built through buildNpmPackage, which is where the npm dependencies are
  # fetched under a fixed-output hash.
  #
  # `chmod` because the store copy is read-only and hatchling writes into the
  # tree it builds from.
  preBuild = ''
    mkdir -p src/node_graph_widget/static
    cp -r ${node-graph-widget-js}/. src/node_graph_widget/static/
    chmod -R u+w src/node_graph_widget/static
  '';

  dependencies = [ anywidget ];

  # `ensured-targets` in pyproject.toml already fails the build if widget.js is
  # missing, but only after hatchling has run; this says the same thing at the
  # point the file is supposed to be there, and covers the css, which the
  # ensured-targets list does not name.  Both come out of one esbuild run —
  # js/widget.tsx does `import "./widget.css"`.
  postInstall = ''
    for f in widget.js widget.css; do
      test -s "$out/${python.sitePackages}/node_graph_widget/static/$f" \
        || (echo "missing frontend asset: $f" >&2; exit 1)
    done
  '';

  # tests/test_widget.py drives a browser through playwright, and
  # tests/notebooks/ is a yarn project for it to serve.  Neither is something a
  # build sandbox can host, and playwright would want to download browsers.  So
  # the import check is the check — it is not vacuous here, because importing
  # the module is what reads widget.js and widget.css off disk.
  doCheck = false;

  pythonImportsCheck = [
    "node_graph_widget"
    "node_graph_widget.html_template"
  ];

  meta = {
    description = "Jupyter widget for visualising node graphs, built on anywidget";
    homepage = "https://github.com/scinode/node-graph-widget";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
