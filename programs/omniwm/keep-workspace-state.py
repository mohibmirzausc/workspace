"""Merge a new OmniWM seed with the live file's per-workspace runtime state.

Usage: keep-workspace-state.py SEED LIVE  (merged TOML on stdout)

The seed wins for everything except two keys on the pool workspaces (2-10):
`displayName` (the bar label, e.g. "F1 dotfiles") and `layoutType`. The triage
skill manages those at runtime, and a rebuild that re-installs the seed must
not wipe them. Workspace 1 is the user's hand-set workspace, so it always comes
from the seed, as do workspaces the live file does not know about.

A live workspace with no displayName keeps the seed's default, if the seed
has one (e.g. "F1" for workspace 6 once the seed sets key labels),
since a missing key there usually means the live file predates that default
rather than a deliberate clear. So a cleared label comes back as the seed
default on the next seed change. OmniWM never writes an empty displayName (it
stores "" as no key), so there is no way to tell a clear from "never set".

layoutType has no such gap: OmniWM always writes it, so on an existing machine
the live value always wins and the seed's layoutType only matters on a fresh
install. To change a pool workspace's layout, change it live.
"""

import sys
import tomllib

import tomlkit

POOL = {str(n) for n in range(2, 11)}
KEPT = ("displayName", "layoutType")


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
            if value is not None:
                ws[key] = value

    sys.stdout.write(tomlkit.dumps(seed))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
