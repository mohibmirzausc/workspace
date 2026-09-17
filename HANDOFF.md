# Handoff — SketchyBar polish, review cleanup, animated wallpaper

**Branch:** `cleanup-sketchybar-review` → **PR #61** (open, 8 commits, all pushed)
**Working tree:** clean. Everything below is committed.
**Live state:** bar healthy, 0 errors in `~/Library/Logs/sketchybar.log`, wallpaper running.

---

## What shipped

### PR #58 (already merged)
SketchyBar status bar + auto-hidden native menu bar. Then a 4-way review
(logic/completeness, simplicity, bug hunt, security) produced 15 inline
comments. The severe finding is worth knowing about:

**GNU-stat PATH shadowing.** `sketchybarEnv.PATH` had `${pkgs.coreutils}/bin`
ahead of `/usr/bin`, so plugins got GNU `stat`, where `-f` means "filesystem
info" not BSD's format string. Every `stat -f %m` failed, printing a dump whose
first word is `File:`; `$(( ))` read that as a variable and `set -u` killed the
script *before* the `trap` installed — leaking the lock the code existed to
reap. **314 crashes** in the log, and it had wedged both the window island
(frozen on stale pills) and the meeting item (stuck on "No meetings"). Fixed
three ways: coreutils off the PATH, absolute `/usr/bin/stat`, numeric guard.

### PR #61 (open — this is what needs a decision)
1. **Review cleanup**: 5 dead plugin files (~107 lines), 17 dead `COLOR_*` in
   `barEnv`, stale `HANDOFF-sketchybar-glyphs.md`, `.playwright-mcp/` +
   `intake-form.png` untracked and **gitignored** (they recur otherwise).
2. **3-pill window island**, focused one highlighted, slot count driven from
   one `WM_WIN_MAX` variable (was hardcoded `0 1 2` in four places).
3. **Scratchpad filter** — parked windows no longer get pills.
4. **Wallspace** animated wallpaper, declaratively selected + settings pinned.

---

## Open decisions

1. **Merge PR #61?** `MERGEABLE` when GitHub last computed it. CI is red for
   two reasons **also red on `main`**: `attribute 'currentSystem' missing`
   and a `graphite-cli` upstream break. Neither is from this branch.
2. **Fix `flake.nix` `currentSystem`** (one line:
   `builtins.currentSystem or "aarch64-darwin"`). Unblocks green CI so future
   PRs can be gated, and drops the `--impure` requirement. Highest-value
   remaining task.
3. **PRs #57 / #59** were open earlier — check whether they still are.
   Leaving PRs unmerged with `homebrew.onActivation.cleanup = "uninstall"` is
   what silently uninstalled software 3–4 times in an earlier session.

---

## Hard-won facts — do not re-derive these

**bash 3.2 has no `$'\uXXXX'` escape.** macOS ships 3.2.57; `\u`/`\U` arrived
in 4.2 and are passed through as literal text. This was the root cause of the
long-running "`` renders as text" bug — *not* fonts, locale, Nerd Font
packaging, or the config-load path, all of which were investigated and cleared
over multiple sessions. Write glyphs as raw UTF-8 byte escapes:
`$'\xef\x89\x82'`. Works for 4-byte sequences too.

**`sketchybar --query` re-escapes PUA codepoints** as `""` in its JSON,
and `json.loads` decodes that back to one codepoint — so a **broken** value
inspects as a perfect glyph. Confirmed PUA-specific: `é★` returns raw UTF-8 in
the same output. Check raw query bytes, or look at the bar.

**Writing test scripts via an unquoted heredoc decodes the escapes**, so a
"minimal repro" contains real glyph bytes and passes while the actual file
fails. The two look identical in any text diff. This cost a long detour.

**`ps %cpu` is a lifetime average.** It read 19–49% for a process whose real
instantaneous rate was under 1%. Sample cumulative CPU-time deltas instead
(`ps -o time=`), divided by wall time.

**Ghostty's `background-opacity` is NOT `kCGWindowAlpha`.** The window reports
`alpha=1.0` while its background *color* is translucent, giving per-pixel alpha
in the framebuffer. The window server composites the desktop beneath. I
claimed the wallpaper would be invisible behind tiled windows; it is plainly
visible, verified by setting a magenta wallpaper and watching it bleed through.

**Wallspace's settings window renders a live wallpaper preview.** Measuring CPU
with it open gave ~27%; closed, the real cost is ~4–7%, and 0.2% once the
desktop is occluded. The tell was a benchmark where 60fps came out *cheaper*
than 15fps — impossible, so the method was broken, not the data.

**Nix indented-string gotchas** (both silently dropped a whole attribute):
a backslash inside `''…''` is **literal**, so a shell line-continuation arrives
as a real backslash; and a bare `''` in a comment **terminates the string**.

**`programs/sketchybar/helpers/*.swift` must be `git add`ed before it builds.**
The flake reads the git tree, so an untracked file is invisible to Nix and the
activation silently no-ops.

**OmniWM's window title goes stale on rename.** `omniwmctl query windows` keeps
serving the old title after a cmux tab is renamed. CoreGraphics has the live
value, and its `kCGWindowNumber` **is** OmniWM's `windowId` — a stable join.
That's what `helpers/window-titles.swift` exists for. Matching on the title
itself cannot work (renames change it; several cmux windows share one).

**cmux exposes no OS window id.** Its `key`/`active` flags point at the window
the CLI was invoked *from*, not the focused one, and its window ordering does
not line up with OmniWM's (checked — indices 4/5 were offset). Don't retry the
`cmux tree` approach.

---

## Animated wallpaper — how it works

- App: `wallspace` cask (declared in `darwin.nix`). Signed + notarized
  (Developer ID "Harsh Jadon"), hardened runtime, sha256 matches the cask pin.
- Video: `~/Pictures/Wallpapers/cozy-8bit.mp4`, **not tracked in git** (13MB
  would ~double the repo). Drop any MP4 there; activation picks it up.
- Selection: `programs/wallspace/seed-wallpaper.py`, run on activation. There
  is no CLI, no `CFBundleDocumentTypes`, and `wallspace://` only resolves
  gallery IDs — so the script reproduces exactly what the "personal use"
  picker writes (`savedWallpaperKey`, `savedPerMonitorWallpapers`,
  `recentsWallpapersModels`, plus the file at
  `~/Library/Caches/Wallspace/Wallpapers/<key>.mp4`).
  **Skips when Wallspace is running** — it rewrites those keys on quit.
- **No community upload.** That is a separate opt-in path
  (`FullScreenView` → `SignedUploadURLService`). The local path
  (`CustomWallpapersService`) has no network call on it.

**Frame rate is the only input that matters** (measured, UI closed):

| | CPU |
|---|---|
| 60fps | 6.2% |
| 30fps | 4.7% |
| 15fps | 4.3% |
| 30fps at 2× slower playback | 4.3% |
| occluded (windows covering desktop) | 0.2% |

~4% is a floor the agent costs regardless. Playback **speed** doesn't matter
(compositor still redraws per frame). **Duration** doesn't (a loop decodes one
frame at a time; length only costs disk). **Resolution** barely does (a 4K
gallery wallpaper measured the same as this 1080p one — decode runs on the M4
media engine). File is stored at 30fps.

---

## Known-unresolved

- **`bridge.sh` emits `wm_windows_changed` now**, but that was added blind —
  it fixes an inert subscription and hasn't been observed firing for a
  focus-preserving window change (e.g. closing a background window).
- **Focused-scratchpad fallback is untested.** If focus lands on a window the
  visibility filter rejects, the plugin shows it anyway. I could not reproduce
  that state (`omniwmctl command toggle-scratchpad` left them
  `isVisible=false`), so it's a guard, not a verified fix.
- **A narrow `$PENDING` race** in `wm_window_list.sh`: A clears pending, B
  fails the lock and writes pending, A exits — leaving an orphaned flag until
  the next WM event. Self-corrects; window is microseconds. Not worth a
  `flock` rewrite.
- **Raycast shortcuts still need re-recording by hand** (cmux `Caps Lock+G`,
  Chrome, Slack) — recorded against the old 4-modifier hyper;
  `settings.rayconfig` is encrypted.

## Useful commands

```sh
bash install.sh                                        # rebuild (NOT darwin-rebuild directly)
launchctl kickstart -k gui/$(id -u)/org.nixos.sketchybar
launchctl kickstart -k gui/$(id -u)/org.nixos.sketchybar-bridge
tail ~/Library/Logs/sketchybar.log                     # should stay empty
omniwmctl query windows --format json | python3 -m json.tool | head -40
```
