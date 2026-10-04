{ pkgs }:

# programs/omniwm/scratchpads.py as a store-path command, `omniwm-scratchpads
# daemon|status|restore`. The omniwm-scratchpads launchd agent in darwin.nix
# runs it, and programs/omniwm.nix puts it on PATH for the hand-run modes.
#
# A store path rather than a home-manager link under ~/.config: nix-darwin
# loads launchd agents BEFORE home-manager links files, so an agent pointed
# at a link can start before the link exists (it exits 2, "can't open file",
# and launchd respawns it until the link shows up). The script is part of
# this derivation, so it exists by the time anything can run it.

pkgs.writeShellScriptBin "omniwm-scratchpads" ''
  exec ${pkgs.python3}/bin/python3 ${./scratchpads.py} "$@"
''
