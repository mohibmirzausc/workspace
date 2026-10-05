# `mem`: the agent memory CLI (ledger, librarian, trace, stats), run from its
# repo checkout so it always matches the code the Pi extension loads.
#
# The memory code targets Node 26 (type stripping, no build step), so this
# pins nixpkgs' nodejs_26 instead of whichever node is first on PATH (nix's
# default nodejs is 24; Homebrew's 26 is only there as a Pi dependency).
{ pkgs, memHome }:

pkgs.writeShellApplication {
  name = "mem";
  runtimeInputs = [ pkgs.nodejs_26 ];
  text = ''
    entry="${memHome}/src/cli/mem.ts"
    if [ ! -f "$entry" ]; then
      echo "mem: no memory checkout at ${memHome} (expected $entry)" >&2
      exit 1
    fi
    exec node "$entry" "$@"
  '';
}
