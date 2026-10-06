#!/usr/bin/env bash
# pi-bootstrap -- install the Pi packages this config expects.
#
# Pi records installed packages in ~/.pi/agent/settings.json, which Pi itself
# writes at runtime. Nix cannot manage that file without breaking Pi's ability
# to save its own settings, so package installs are a manual step. This script
# is that step, kept in the repo so a new machine is one command away rather
# than a memory exercise.
#
# Idempotent: `pi install` on an already-installed package is a no-op refresh.
set -euo pipefail

packages=(
  # MO security baseline: file protection, path access, permission gates.
  "git:github.com/mechanical-orchard/pi-guardrails@v0.15.0"

  # Agent-to-agent messaging between Pi sessions (Pi's analogue of Claude's
  # SendMessage/ListAgents, which Pi lacks). Same machine only.
  "npm:pi-intercom"

  # Sub-agent delegation and parallel dispatch. Pi ships no sub-agents by
  # design; several shared skills assume them. Lazily loaded, so it costs
  # almost no context until used.
  "npm:pi-subagents"

  # Momentum story tracking. The skill lives at plugins/momentum/skills in
  # that repo rather than a top-level skills/, so Pi's auto-discovery misses
  # it -- home.activation.linkMomentumSkillForPi links it after install.
  "git:github.com/mechanical-orchard/momentum-tracker"
)

command -v pi >/dev/null || {
  echo "pi not found on PATH. It comes from the pi-coding-agent brew in" >&2
  echo "darwin.nix -- run a darwin rebuild first." >&2
  exit 1
}

for p in "${packages[@]}"; do
  echo "==> $p"
  pi install "$p"
done

# MCP servers.
#
# Pi 1.0 added a built-in MCP client -- `pi mcp add/list/login/logout`, with
# OAuth handled natively. Before 1.0 Pi had no MCP at all ("No MCP. Build CLI
# tools with READMEs"), which is why every other integration here is a CLI or
# a skill instead. Slack and Notion are the two that could not be re-homed
# that way: both are remote OAuth-only services, so there is no token to put
# in sops and no REST call to wrap.
#
# `--exposure codemode` is Pi's default and the reason this is affordable.
# Tool definitions are NOT injected into the system prompt; Pi loads them on
# demand. Claude pays ~11k-29k tokens per request for the equivalent, used or
# not. A consequence worth remembering: these tools will not show up in a
# tool list, which is normal and not evidence they are broken.
#
# `pi mcp add` replaces an existing entry of the same name, so re-running is
# safe. It only writes ~/.pi/agent/mcp.json -- URLs and a public client id,
# no secrets. Tokens arrive only at `pi mcp login`, below.
echo
echo "==> mcp: slack"
pi mcp add slack \
  --url https://mcp.slack.com/mcp \
  --oauth-client-id 1601185624273.8899143856786 \
  --oauth-callback-port 3118 \
  --description 'Slack workspace: read and search channels, threads, users; send messages'

# Slack needs the pre-registered client id and fixed callback port above
# because its auth server advertises `registration_endpoint: null` -- dynamic
# client registration is unsupported. Notion supports it, so it needs neither.
#
# That client id is Claude's Slack app, and Slack matches the redirect URI
# exactly. The app registers `http://localhost:3118/callback`, but
# `--oauth-callback-port` makes Pi send `http://127.0.0.1:3118/callback`, so
# sign-in fails with "redirect_uri did not match any configured URIs". Pi's
# `oauth.callbackUrl` is sent as written, but `pi mcp add` has no flag for it,
# so set it here. This runs after every `pi mcp add`, which replaces the entry.
mcp_json="$HOME/.pi/agent/mcp.json"
jq '.mcpServers.slack.oauth.callbackUrl = "http://localhost:3118/callback"' \
  "$mcp_json" > "$mcp_json.tmp"
mv "$mcp_json.tmp" "$mcp_json"

echo "==> mcp: notion"
pi mcp add notion \
  --url https://mcp.notion.com/mcp \
  --description 'Notion workspace: search, read and update pages and databases'

echo
echo "Installed. Run 'homeswitch' next so the Momentum skill gets linked,"
echo "then 'pi list' to confirm."
echo
echo "Then sign in to the OAuth servers -- these open a browser, so they are"
echo "not scripted here, and they are the only step that stores a secret."
echo "They are the one expected exception to the pi.md rule about commands"
echo "that prompt for credentials; run them yourself, deliberately:"
echo "    pi mcp login slack"
echo "    pi mcp login notion"
echo
echo "Quit the Notion desktop app first. It claims mcp.notion.com as a"
echo "universal link, so the sign-in opens there instead of a browser and"
echo "fails with a misleading \"check your internet connection\". If you would"
echo "rather leave it running, copy the URL pi prints and open it with:"
echo "    open -b com.google.chrome '<the full authorize URL>'"
echo
echo "Confirm with 'pi mcp list' (it exits 1 while any server needs sign-in)."
