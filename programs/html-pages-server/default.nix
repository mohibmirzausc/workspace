{ pkgs }:

# Always-on local gallery server for pages produced by the `html-page` Claude
# skill. Wraps server.js (Node stdlib only) so it runs with no npm install.
# Honors $HTML_PAGES_DIR (default ~/html-pages) and $PORT (default 7777).

let
  serverJs = ./server.js;
in
pkgs.writeShellScriptBin "html-pages-server" ''
  exec ${pkgs.nodejs}/bin/node ${serverJs} "$@"
''
