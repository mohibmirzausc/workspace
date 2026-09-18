#!/usr/bin/env python3
"""Point Wallspace at a local video, without using its UI.

Wallspace has no CLI and its wallspace:// deep link only accepts gallery
wallpaper IDs, so the only supported way to select a local file is its
"Select an MP4 video for personal use" picker. This reproduces what that
picker writes, so the choice survives a fresh machine.

IMPORTANT: this is NOT the community upload path. That lives in FullScreenView
(SignedUploadURLService, "requesting signed upload URL") and is a separate,
opt-in action. Nothing here talks to the network -- CustomWallpapersService
and the keys written below are pure local state.

Schema was reverse-engineered from a real selection; Wallspace stores:
  savedWallpaperKey          int, the active wallpaper's key
  savedPerMonitorWallpapers  JSON, {displayID: {key, masterUrlString}}
  recentsWallpapersModels    JSON array of full wallpaper models
and expects the video itself at ~/Library/Caches/Wallspace/Wallpapers/<key>.mp4

Wallspace MUST NOT be running: it writes these keys on quit and would clobber
whatever we set.
"""
import base64
import json
import os
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
PLIST = f"{HOME}/Library/Preferences/wallspace.app.plist"
CACHE = f"{HOME}/Library/Caches/Wallspace/Wallpapers"
DOMAIN = "wallspace.app"

# Fixed high key so re-running replaces our entry instead of stacking copies.
# Wallspace's own keys are ~15-digit ids from its API; 9e14 will not collide.
KEY = 900000000000001


def read_json_key(key):
    r = subprocess.run(["plutil", "-extract", key, "raw", "-o", "-", PLIST],
                       capture_output=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(base64.b64decode(r.stdout))
    except Exception:
        return None


def write_json_key(key, value):
    blob = json.dumps(value, separators=(",", ":")).encode()
    subprocess.run(["defaults", "write", DOMAIN, key, "-data", blob.hex()],
                   check=True)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else f"{HOME}/Pictures/Wallpapers/cozy-8bit.mp4"
    if not os.path.isfile(src):
        print(f"seed-wallpaper: no such video: {src}", file=sys.stderr)
        return 1
    if subprocess.run(["pgrep", "-f", "Wallspace.app/Contents/MacOS"],
                      capture_output=True).returncode == 0:
        print("seed-wallpaper: Wallspace is running; skipping "
              "(it would overwrite these keys on quit)")
        return 0

    os.makedirs(CACHE, exist_ok=True)
    dest = f"{CACHE}/{KEY}.mp4"
    if not os.path.exists(dest) or os.path.getsize(dest) != os.path.getsize(src):
        shutil.copy2(src, dest)

    model = {
        "resolution": "1920×1080",
        "videoUrl": f"file://{dest}",
        "is_4k": False,
        "is_from_desktop_hut": False,
        "title": "Cozy 8-bit",
        "is_pro": False,
        "downloads": 0,
        "id": "00000000-0000-0000-0000-000000000001",
        "likes": 0,
        "masterUrl": f"file://{dest}",
        "fileSize": f"{os.path.getsize(src) // (1024 * 1024)}MB",
        "for_lockscreen": False,
        "key": KEY,
        "previewhdUrl": f"file://{dest}",
        "posterUrl": "",
        "createdAt": "2026-09-17T00:00:00.000000+00:00",
        "category": "Personal",
        "duration": "0:19s",
        "slug": "cozy-8bit",
    }

    recents = [m for m in (read_json_key("recentsWallpapersModels") or [])
               if m.get("key") != KEY]
    write_json_key("recentsWallpapersModels", [model] + recents)

    per_mon = read_json_key("savedPerMonitorWallpapers") or {}
    # Reuse the existing display id when present so we match this panel, and
    # fall back to the built-in display's shape on a fresh install.
    disp = next(iter(per_mon), "Built-in Retina Display_1512x982")
    per_mon[disp] = {"displayPersistenceID": disp, "key": KEY,
                    "masterUrlString": f"file://{dest}"}
    write_json_key("savedPerMonitorWallpapers", per_mon)

    subprocess.run(["defaults", "write", DOMAIN, "savedWallpaperKey",
                    "-int", str(KEY)], check=True)
    print(f"seed-wallpaper: set {os.path.basename(src)} as the Wallspace wallpaper")
    return 0


if __name__ == "__main__":
    sys.exit(main())
