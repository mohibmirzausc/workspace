#!/usr/bin/env bash
# WM -> sketchybar event bridge.
#
# Reads the active window manager's event stream and normalizes it onto three
# sketchybar triggers (see ./README.md):
#   wm_workspace_changed  WM_BACKEND WM_WORKSPACE
#   wm_windows_changed    WM_BACKEND WM_WORKSPACE WM_WINDOW_COUNT
#   wm_focus_changed      WM_BACKEND WM_WORKSPACE WM_APP WM_TITLE
#
# Invoked as: bridge.sh <backend>
# Requires `jq` and `sketchybar` on PATH; exits 0 (not 1) when either is
# missing so the launchd agent does not respawn-loop on an unfinished setup.
set -uo pipefail

backend="${1:?usage: bridge.sh <paneru|omniwm|rift|nehir>}"

log() { printf '[wm-sketchybar-bridge:%s] %s\n' "$backend" "$*" >&2; }

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "$1 not found on PATH; bridge idle. $2"
    exit 0
  fi
}

need sketchybar "Set sketchybar = false in choice.nix, or install it."
need jq "This should not happen; jq is a nix dependency of the bridge."

# rift honors this; leaving it set would make events multi-line pretty JSON.
unset RIFT_CLI_PRETTY

# ---------------------------------------------------------------------------
# Wire format between jq and the dispatch loop.
#
# Fields are joined with ASCII Unit Separator (0x1F), NOT tab. Tab is IFS
# whitespace, so bash `read` collapses runs of tabs and an event with an empty
# middle field would silently shift every later field left. 0x1F is
# non-whitespace, so empty fields survive.
#
# jq consumes a *stream of JSON values*, not lines: nehirctl is documented to
# pretty-print its envelopes, which line-oriented parsing would choke on.
# ---------------------------------------------------------------------------
jq_prelude='
  def emit($e; $ws; $n; $app; $title):
    [ $e,
      (if $ws == null then "" else ($ws | tostring) end),
      (if $n  == null then "" else ($n  | tostring) end),
      (if $app == null then "" else ($app | tostring) end),
      (if $title == null then "" else ($title | tostring) end)
    ] | join("\u001f");

  # Name-priority field extraction for OmniWM and nehir, whose subscription
  # payloads sit at .result.payload but whose exact key spelling is not pinned
  # down in their published docs (OmniWM documents workspace *query* fields in
  # kebab-case and workspace-bar pills in camelCase).
  #
  # Priority is by NAME, not by document position. An earlier document-order
  # version of this was a real bug: the OmniWM active-workspace payload is
  #   { display: {id,isMain,name}, workspace: {displayName,id,number,rawName} }
  # and a plain recursive descent reaches display.name before workspace.rawName,
  # so the bar showed "LG HDR 4K" as the workspace name. Candidate names are
  # therefore tried in order and a specific key always beats a generic one --
  # and bare "name"/"workspace" are deliberately NOT candidates.
  def pickby($names):
    first(
      $names[] as $n
      | [ .. | objects | to_entries[]
          | select((.key | ascii_downcase) == ($n | ascii_downcase))
          | .value
          | select(type == "string" or type == "number")
          | select(. != "")
        ][0]
      | select(. != null)
    ) // null;

  def pickcount($arrays; $numbers):
    (first($arrays[] as $n
           | [ .. | objects | to_entries[]
               | select((.key | ascii_downcase) == ($n | ascii_downcase))
               | .value | select(type == "array") | length ][0]
           | select(. != null)) // null)
    // (first($numbers[] as $n
              | [ .. | objects | to_entries[]
                  | select((.key | ascii_downcase) == ($n | ascii_downcase))
                  | .value | select(type == "number") ][0]
              | select(. != null)) // null);

  def ws_names: ["rawName","raw-name","workspaceName","workspace-name",
                 "displayName","display-name","workspaceNumber","number"];
  def app_names: ["appName","app-name","bundleId","bundle-id","app"];
  def title_names: ["windowTitle","window-title","title",
                    "newTitle","new-title"];
'

# ---------------------------------------------------------------------------
# Per-backend stream command + jq mapping.
# ---------------------------------------------------------------------------
case "$backend" in
  paneru)
    need paneru "Is services.paneru enabled and on PATH?"
    # Event shapes verified against the PINNED revision's
    # crates/shared_types/src/state.rs `enum StateEvent` (serde snake_case,
    # tag flattened into an "event" field) -- not against the published docs,
    # which are written for whatever HEAD happens to be.
    #
    # Two traps here, both confirmed against a live capture:
    #   * `windows_changed` carries only { virtual_workspace_number, active },
    #     and `active` is an ActiveState with no window list. There is no count
    #     in it at all.
    #   * `on_screen_changed` is the event with `windows: [WindowState]`, and it
    #     is also the only event covering plain moves and resizes. Missing it
    #     means the bar never learns a window count and never refreshes on a
    #     resize.
    # So the count comes from on_screen_changed, filtered to the active display
    # (its window list spans every display).
    stream=(paneru subscribe --json)
    jq_map='
      if .event == "virtual_workspace_changed" then
        emit("wm_workspace_changed"; .active.virtual_workspace_number; null; null; null)
      elif .event == "on_screen_changed" then
        # $dpy must be bound outside the .windows[] iteration: inside it,
        # .active would resolve against the window object, not the envelope.
        (.active.display_id) as $dpy
        | emit("wm_windows_changed"; .active.virtual_workspace_number;
               ([ .windows[]?
                  | select($dpy == null or .display_id == null
                           or .display_id == $dpy)
                ] | length);
               null; null)
      elif .event == "windows_changed" then
        emit("wm_windows_changed"; .virtual_workspace_number; null; null; null)
      elif .event == "window_focused" then
        emit("wm_focus_changed"; .virtual_workspace_number; null; .bundle_id; .title)
      elif .event == "window_title_changed" then
        emit("wm_focus_changed"; null; null; null; .title)
      elif .event == "display_changed" then
        emit("wm_workspace_changed"; null; null; null; null)
      else empty end
    '
    ;;

  rift)
    need rift-cli "Is the acsandmann/tap/rift formula installed?"
    # `subscribe mach` is the streaming form: one compact JSON value per event
    # on stdout. `subscribe cli` is NOT usable here -- it registers a child
    # command with rift and delivers data as RIFT_* env vars, not on stdout.
    #
    # Event shapes verified against crates/rift-protocol/src/events.rs
    # (serde tag = "type", snake_case).
    #
    # focused_window_changed carries only window_id, no app or title, so the
    # app name comes from sketchybar's own front_app_switched event instead.
    stream=(rift-cli subscribe mach '*')
    jq_map='
      if .type == "workspace_changed" then
        emit("wm_workspace_changed"; .workspace_name; null; null; null)
      elif .type == "windows_changed" then
        emit("wm_windows_changed"; .workspace_name;
             (if (.windows | type) == "array" then (.windows | length) else null end);
             null; null)
      elif .type == "window_title_changed" then
        emit("wm_focus_changed"; .workspace_name; null; null; .new_title)
      elif .type == "focused_window_changed" then
        emit("wm_focus_changed"; .workspace_name; null; null; null)
      else empty end
    '
    ;;

  omniwm|nehir)
    if [ "$backend" = "omniwm" ]; then
      need omniwmctl "Is the omniwm cask installed?"
      # --reconnect survives a relaunch; ndjson keeps envelopes on one line.
      stream=(omniwmctl subscribe workspace-bar --reconnect --format ndjson)
    else
      need nehirctl "Is the guria/tap/nehir cask installed?"
      # nehirctl has no --format flag and is documented to pretty-print, which
      # is why jq runs in value-stream rather than line mode (see above).
      stream=(nehirctl subscribe workspace-bar)
    fi

    # Both are the same engine (nehir is an OmniWM fork) and both expose a
    # `workspace-bar` channel, which is the projection their own bar renders.
    # One event carries everything this bridge needs, verified against a live
    # OmniWM 0.6.10 capture:
    #
    #   result.payload.interactionMonitorId : "display:5"
    #   result.payload.monitors[] : { id, name, workspaces[] }
    #     workspaces[] : { rawName, displayName, number, isFocused,
    #                      windows[] : { appName, bundleId, isFocused,
    #                                    windowCount,
    #                                    allWindows[]: { title, isFocused } } }
    #
    # Deliberately NOT using active-workspace + windows-changed + focus:
    #   * windows-changed lists every managed window including ones with
    #     hiddenReason = "workspace-inactive", so its length is the global
    #     window count, not the visible one (9 windows, 0 visible, in a live
    #     capture on a single workspace).
    #   * the focus channel delivered an empty payload {} in that same capture.
    # workspace-bar avoids both problems and is scoped to the interaction
    # monitor, so the count matches what is actually on screen.
    #
    # IPC must be enabled. On OmniWM 0.6.10 `general.ipcEnabled = true` in
    # settings.toml is NOT sufficient -- it also needs "Enable IPC" from the
    # menu bar icon once.
    jq_map='
      if (.channel // "") != "workspace-bar" then empty else
        (.result.payload // .payload // .) as $p |
        ($p.interactionMonitorId) as $mon |
        ( [ $p.monitors[]? | select($mon == null or .id == $mon) ][0]
          // ($p.monitors[0]? ) ) as $m |
        ( [ $m.workspaces[]? | select(.isFocused) ][0] ) as $ws |
        if $ws == null then empty else
          ( $ws.rawName // $ws.displayName // $ws.number ) as $name |
          ( [ $ws.windows[]? | .windowCount // 1 ] | add // 0 ) as $count |
          ( [ $ws.windows[]? | select(.isFocused) ][0] ) as $focused |
          emit("wm_workspace_changed"; $name; $count; null; null),
          ( if $focused == null then empty else
              emit("wm_focus_changed"; $name; null;
                   $focused.appName // $focused.bundleId;
                   ( [ $focused.allWindows[]? | select(.isFocused) | .title ][0]
                     // ($focused.allWindows[0]?.title) ))
            end )
        end
      end
    '
    ;;

  none)
    log 'backend is "none"; nothing to bridge.'
    exit 0
    ;;

  *)
    log "unknown backend \"$backend\""
    exit 0
    ;;
esac

log "bridging ${stream[*]} -> sketchybar"

# If a backend ever writes non-JSON to stdout, jq aborts and this process
# exits; the launchd agent has KeepAlive with ThrottleInterval=5, so it comes
# back a few seconds later rather than spinning.
"${stream[@]}" 2>/dev/null \
  | jq -r --unbuffered "$jq_prelude $jq_map" \
  | while IFS=$'\037' read -r event ws count app title; do
      [ -n "${event:-}" ] || continue
      args=("$event" "WM_BACKEND=$backend")
      [ -n "${ws:-}" ] && args+=("WM_WORKSPACE=$ws")
      [ -n "${count:-}" ] && args+=("WM_WINDOW_COUNT=$count")
      [ -n "${app:-}" ] && args+=("WM_APP=$app")
      [ -n "${title:-}" ] && args+=("WM_TITLE=$title")
      sketchybar --trigger "${args[@]}" >/dev/null 2>&1 || true
    done

log "event stream ended"
