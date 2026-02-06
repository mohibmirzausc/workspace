{ pkgs }:

let
  tree-me = pkgs.writeShellScriptBin "tree-me" (builtins.readFile ./tree-me.sh);
  git-clone-wt = pkgs.writeShellScriptBin "git-clone-wt" (builtins.readFile ./git-clone-wt.sh);
in
{
  tree-me = tree-me;
  git-clone-wt = git-clone-wt;
}
