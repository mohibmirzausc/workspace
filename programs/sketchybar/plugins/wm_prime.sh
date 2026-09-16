#!/usr/bin/env bash
# Prime the WM items at sketchybar startup.
#
# paneru and rift only emit subscription events on change, so right after a
# sketchybar restart the workspace pills would all look inactive until the next
# switch. Query the active workspace once and fire the trigger ourselves.
# OmniWM and nehir send initial snapshots on subscribe, so this is belt and
# braces for them.
set -u
sleep 1

backend=$(wm status 2>/dev/null | awk '/^backend:/ {print $2}')
[ -n "${backend:-}" ] || exit 0

ws=""
case "$backend" in
  paneru)
    command -v paneru >/dev/null 2>&1 &&
      ws=$(paneru query active --json 2>/dev/null \
             | jq -r '.virtual_workspace_number // empty' 2>/dev/null)
    ;;
  rift)
    command -v rift-cli >/dev/null 2>&1 &&
      ws=$(rift-cli query workspaces 2>/dev/null \
             | jq -r 'first(.. | objects | select(.is_focused == true or .is_current == true)
                      | (.name // .workspace_name // empty))' 2>/dev/null)
    ;;
  omniwm)
    # Target workspace.rawName explicitly. A recursive descent reaches
    # display.name ("LG HDR 4K") before workspace.rawName, and the field is
    # camelCase (rawName), not kebab -- same bug the bridge documents.
    command -v omniwmctl >/dev/null 2>&1 &&
      ws=$(omniwmctl query active-workspace 2>/dev/null \
             | jq -r '(.result.payload.workspace.rawName
                      // .result.payload.workspace.displayName
                      // (.result.payload.workspace.number|tostring)) // empty' 2>/dev/null)
    ;;
  nehir)
    command -v nehirctl >/dev/null 2>&1 &&
      ws=$(nehirctl query active-workspace 2>/dev/null \
             | jq -r 'first(.. | objects | (.workspaceName // .name // empty)
                      | select(type == "string"))' 2>/dev/null)
    ;;
esac

[ "$ws" = "null" ] && ws=""
args=("wm_workspace_changed" "WM_BACKEND=$backend")
[ -n "${ws:-}" ] && args+=("WM_WORKSPACE=$ws")
sketchybar --trigger "${args[@]}" >/dev/null 2>&1 || true
