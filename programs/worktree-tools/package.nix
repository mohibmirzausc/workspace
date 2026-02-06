{ pkgs }:

let
  tree-me = pkgs.writeShellScriptBin "tree-me" (builtins.readFile ./tree-me.sh);
in
{
  tree-me = tree-me;
}
