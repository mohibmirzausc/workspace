#!/usr/bin/env bash
# pi-bootstrap -- install the Pi packages this config expects.
#
# Pi records installed packages in ~/.pi/agent/settings.json, which Pi itself
# writes at runtime. Nix cannot manage that file without breaking Pi's ability
# to save its own settings, so package installs are a manual step. This script
# is that step, kept in the repo so a new machine is one command away rather
# than a memory exercise.
#
# Idempotent, and safe to re-run to pick up new package versions: `pi install`
# is a no-op refresh once a package exists, so each install is followed by
# `pi update --extension` to actually upgrade it. See the loop below.
set -euo pipefail

# --packages-only: install/update the Pi packages and check them, then stop.
# install.sh runs it this way after every rebuild, so Pi (from brew) and its
# packages (from npm/git) move together instead of drifting apart. The MCP
# setup below is skipped: it replaces server entries and prints sign-in steps,
# which belong to a deliberate first-time setup, not every rebuild.
packages_only=0
for arg in "$@"; do
  case "$arg" in
    --packages-only) packages_only=1 ;;
    *) echo "usage: pi-bootstrap [--packages-only]" >&2; exit 2 ;;
  esac
done

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
  # `pi install` on an already-installed package is a no-op refresh, not an
  # upgrade -- it reports "Installed" and leaves the old version in place. So
  # on an existing machine this script would otherwise freeze every package at
  # whatever version it first installed, while a new machine got latest.
  #
  # That bit once: pi-subagents stayed at 0.73.1, which failed to start
  # background children with "Background children require the host npm package
  # ... does not provide @earendil-works/pi-agent-core/node". That subpath does
  # not exist in any published pi-agent-core; upstream made the alias optional
  # in 0.75.0. Re-running the bootstrap could not have fixed it.
  #
  # `pi update` honours a pinned ref -- @v0.15.0 refetches that tag rather than
  # moving off it -- so this is safe for the pinned entries above.
  pi update --extension "$p"
done

# Compatibility check: can pi-subagents start background children on this Pi?
#
# Pi and pi-subagents are released separately. pi-subagents launches background
# children through a runner that aliases the host Pi's packages, and it refuses
# to launch when one it expects is missing. Pi 1.2.0 removed its chord
# dependency while pi-subagents 0.76.1 still demanded it, so every background
# child failed with "... does not provide @earendil-works/chord" -- and nothing
# said so until an agent tried to delegate. This asks pi-subagents' own check
# (resolveHostPeerAliases, the function behind that error) and reports the
# result here, at install time. It is a warning, never a failure.
check_subagents() {
  local agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  local aliases="$agent_dir/npm/node_modules/pi-subagents/src/runs/background/runner-aliases.js"
  local pi_bin prefix host=""
  pi_bin=$(readlink -f "$(command -v pi)")
  prefix=$(dirname "$(dirname "$pi_bin")")
  for candidate in "$prefix/libexec/lib/node_modules/@earendil-works/pi-coding-agent" \
                   "$prefix/lib/node_modules/@earendil-works/pi-coding-agent"; do
    [ -f "$candidate/package.json" ] && { host="$candidate"; break; }
  done
  if [ ! -f "$aliases" ] || [ -z "$host" ]; then
    echo "==> pi-subagents check skipped (couldn't find its runner or the Pi package)"
    return 0
  fi
  echo "==> pi-subagents background children on Pi $(pi --version 2>/dev/null)"
  node --input-type=module -e '
    const [aliasesFile, host] = process.argv.slice(1);
    const { resolveHostPeerAliases } = await import(aliasesFile);
    const { missing } = resolveHostPeerAliases(host);
    if (missing.length === 0) { console.log("    ok: every host package the child runner needs is present"); process.exit(0); }
    console.log("    WARNING: background children will fail to start. Missing from the Pi package:");
    for (const m of missing) console.log("      " + m);
    console.log("    pi-subagents and this Pi are out of step: update pi-subagents, or wait for a release that supports this Pi.");
    process.exit(1);
  ' "$aliases" "$host" || return 1
}
subagents_ok=1
check_subagents || subagents_ok=0

if [ "$packages_only" -eq 1 ]; then
  [ "$subagents_ok" -eq 1 ] || exit 3
  exit 0
fi

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
