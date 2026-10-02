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

echo
echo "Installed. Run 'homeswitch' next so the Momentum skill gets linked,"
echo "then 'pi list' to confirm."
