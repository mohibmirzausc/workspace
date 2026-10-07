{ pkgs }:

# programs/cmux/attention.py as a store-path command, `cmux-attention
# hook|daemon|jump|snapshot`. Every caller (the cmux-attention launchd agent
# in darwin.nix, the notification hook in programs/cmux.nix, Caps+U in
# programs/karabiner.nix, the sketchybar bell via WM_ATTENTION_CMD) runs this
# rather than a home-manager link under ~/.config/cmux.
#
# Why: nix-darwin loads launchd agents BEFORE home-manager links files, so on
# the rebuild that added the agent it started against a
# ~/.config/cmux/attention.py that did not exist yet, exited 2 ("can't open
# file") and was respawned until the link appeared. A store path exists by
# the time anything can reference it.
#
# The triage skill is copied in beside it, laid out like the repo
# (cmux/attention.py, agents/skills/triage/), so attention.py's
# _import_inventory finds the inventory module that was built with it rather
# than whatever ~/.claude/skills/triage holds at that moment.
#
# The existence check cannot fail for a store path in this closure; it is the
# same rule as the agent's own "dependency missing" exits (exit 0 with one log
# line, so KeepAlive.SuccessfulExit = false leaves it stopped instead of
# respawn-looping). `hook` passes its input through instead, because a hook
# that prints nothing makes cmux post a failure alert.

let
  share = pkgs.runCommand "cmux-attention-share" { } ''
    mkdir -p $out/cmux $out/agents/skills
    cp ${./attention.py} $out/cmux/attention.py
    cp -r ${../agents/skills/triage} $out/agents/skills/triage
  '';
  script = "${share}/cmux/attention.py";
in
pkgs.writeShellScriptBin "cmux-attention" ''
  if [ ! -f ${script} ]; then
    if [ "''${1:-}" = hook ]; then exec /bin/cat; fi
    echo "$(/bin/date +%H:%M:%S) cmux-attention: ${script} missing; idle." >&2
    exit 0
  fi
  exec ${pkgs.python3}/bin/python3 ${script} "$@"
''
