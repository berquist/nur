{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "node-graph-widget-js";
  version = "0.0.5-unstable-2025-11-27";

  # The same repository as ../node-graph-widget, built twice: once here for the
  # esbuild bundle, once there for the Python package that carries it.  The
  # bundle is not committed upstream — `js/widget.tsx` is — so there is no way
  # to skip this and still have a widget that renders.
  src = fetchFromGitHub {
    owner = "scinode";
    repo = "node-graph-widget";
    rev = "171ef0579adbc28f430fdbcf5bf9ee54a425a258";
    hash = "sha256-u7kfu5bGw6044Y3x0sKFuaTYzCEi5LwSjUAn9nsOSeI=";
  };

  npmDepsHash = "sha256-y+iwhRFPUTen3tvVL3xLijsJF5iRFPbdkg8RmUG0HyY=";

  # package.json declares neither `name` nor `version`, and the root entry of
  # package-lock.json mirrors that.  `npm ci` reads both, and the paths that
  # object to an unnamed root package do so before fetching anything, so this
  # is written in rather than left to chance.  The values go no further than
  # this build: nothing consumes the npm metadata, only the bundle.
  #
  # One line each, and tabs.  Both files are tab-indented, and a multi-line
  # replacement inside a Nix `''` string has its leading whitespace rewritten
  # by the dedent — mixing that with tabs is a good way to write a pattern that
  # silently matches nothing.  JSON does not care that the keys share a line.
  # The lockfile anchor is the root package entry rather than its
  # `"dependencies"` line, which appears 115 times.
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '	"scripts": {' '	"name": "node-graph-widget", "version": "0.0.5", "scripts": {'

    substituteInPlace package-lock.json \
      --replace-fail '		"": {' '		"": { "name": "node-graph-widget", "version": "0.0.5",'
  '';

  npmBuildScript = "build";

  # esbuild writes into the Python package's data directory, which is where
  # ../node-graph-widget expects to find it — see the `preBuild` there, which
  # copies this output back into the same relative path so hatch-jupyter-builder's
  # `skip-if-exists` fires and no npm runs at Python build time.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r src/node_graph_widget/static/. "$out/"

    runHook postInstall
  '';

  # The bundle is one minified widget.js plus its css.  If esbuild ever stops
  # producing it the copy above would silently install an empty directory, and
  # the Python build's `ensured-targets` would be the thing that failed, three
  # derivations away from the cause.
  postInstall = ''
    test -s "$out/widget.js" \
      || (echo "esbuild produced no widget.js" >&2; exit 1)
  '';

  meta = {
    description = "esbuild bundle for the node-graph anywidget frontend";
    homepage = "https://github.com/scinode/node-graph-widget";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ berquist ];
  };
}
