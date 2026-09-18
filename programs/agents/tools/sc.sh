#!/usr/bin/env bash
# sc -- Shortcut CLI for coding agents.
#
# Replaces the @shortcut/mcp MCP server, which costs ~45 tool definitions
# (roughly 11k-29k tokens) in every request whether or not Shortcut is used.
# This CLI costs only what its skill's SKILL.md costs (~250 tokens), and the
# agent already knows how to run a command and pipe it to jq.
#
# The token is read from the sops store at call time, so it is never written
# into a config file on disk.
set -euo pipefail

API="https://api.app.shortcut.com/api/v3"
SECRETS="$HOME/src/workspace/programs/sops/secrets.yaml"

die() { echo "sc: $*" >&2; exit 1; }

token() {
  [ -n "${SHORTCUT_API_TOKEN:-}" ] && { printf '%s' "$SHORTCUT_API_TOKEN"; return; }
  [ -f "$SECRETS" ] || die "no secrets file at $SECRETS and SHORTCUT_API_TOKEN unset"
  SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
    sops --decrypt --output-type json "$SECRETS" 2>/dev/null \
    | jq -er '.shortcut_api_token' 2>/dev/null \
    || die "could not read shortcut_api_token from sops"
}

api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" \
    -H "Shortcut-Token: $(token)" \
    -H "Content-Type: application/json" \
    "$@" "$API$path"
}

usage() {
  cat <<'USAGE'
sc -- Shortcut CLI

  sc me                        current member (name, id, mention)
  sc story <id>                fetch one story
  sc search <query>            search stories (Shortcut query syntax)
  sc mine                      stories owned by you, not yet done
  sc comment <id> <text>       add a comment to a story
  sc start <id>                move story to its workflow "started" state
  sc raw <METHOD> <PATH> [-d json]   any API v3 call

Output is JSON; pipe to jq. Examples:
  sc story 12345 | jq '{name, url: .app_url}'
  sc search 'owner:mohib.mirza state:"In Progress"' | jq '.data[].name'
USAGE
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  me)      api GET /member ;;
  story)   [ $# -ge 1 ] || die "usage: sc story <id>"; api GET "/stories/$1" ;;
  search)  [ $# -ge 1 ] || die "usage: sc search <query>"
           api GET "/search/stories?query=$(jq -rn --arg q "$1" '$q|@uri')" ;;
  mine)    MENTION=$(api GET /member | jq -r '.mention_name')
           api GET "/search/stories?query=$(jq -rn --arg q "owner:$MENTION !is:done" '$q|@uri')" ;;
  comment) [ $# -ge 2 ] || die "usage: sc comment <id> <text>"
           api POST "/stories/$1/comments" -d "$(jq -n --arg t "$2" '{text:$t}')" ;;
  start)   [ $# -ge 1 ] || die "usage: sc start <id>"
           WF=$(api GET /workflows | jq -r '.[0].states[] | select(.type=="started") | .id' | head -1)
           [ -n "$WF" ] || die "could not find a started workflow state"
           api PUT "/stories/$1" -d "$(jq -n --argjson s "$WF" '{workflow_state_id:$s}')" ;;
  raw)     [ $# -ge 2 ] || die "usage: sc raw <METHOD> <PATH> [-d json]"
           M="$1"; P="$2"; shift 2; api "$M" "$P" "$@" ;;
  help|--help|-h) usage ;;
  *)       die "unknown command: $cmd (try: sc help)" ;;
esac
