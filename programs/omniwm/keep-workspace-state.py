"""Merge a new OmniWM seed with the live file's per-workspace runtime state.

Usage: keep-workspace-state.py SEED LIVE  (merged TOML on stdout)

The seed wins for everything except one key on the pool workspaces (2-10):
`displayName` (the bar label, e.g. "F1 dotfiles"). The triage skill manages it
at runtime, and a rebuild that re-installs the seed must not wipe it. Workspace 1 is the user's hand-set workspace, so it always comes
from the seed, as do workspaces the live file does not know about.

A live workspace with no displayName keeps the seed's default, if the seed
has one (e.g. "F1" for workspace 6 once the seed sets key labels),
since a missing key there usually means the live file predates that default
rather than a deliberate clear. So a cleared label comes back as the seed
default on the next seed change. OmniWM never writes an empty displayName (it
stores "" as no key), so there is no way to tell a clear from "never set".

layoutType is deliberately NOT kept: every workspace is niri, set in the seed,
and triage no longer changes layouts. So a seed change resets any layout
toggled live (Opt+Shift+L) back to the seed's. It used to be kept, when triage
picked dwindle or niri per project; dropping it is also what moves this
machine's old dwindle workspaces to niri on the next rebuild.
"""

import sys
import tomllib

import tomlkit

POOL = {str(n) for n in range(2, 11)}
KEPT = ("displayName",)


def main(seed_path, live_path):
    with open(seed_path, encoding="utf-8") as f:
        seed = tomlkit.parse(f.read())
    with open(live_path, "rb") as f:
        live = tomllib.load(f)

    live_by_name = {ws.get("name"): ws for ws in live.get("workspaces", [])}
    for ws in seed.get("workspaces", []):
        name = ws.get("name")
        if name not in POOL or name not in live_by_name:
            continue
        for key in KEPT:
            value = live_by_name[name].get(key)
            # OmniWM rejects the whole file over a non-string label, and a
            # clean exit here would skip the plain-seed fallback.
            if isinstance(value, str):
                ws[key] = value

    sys.stdout.write(tomlkit.dumps(seed))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
