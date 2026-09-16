# Handoff: SketchyBar `\uf...` glyph bug

**Status:** UNRESOLVED. Bar is functional; only Nerd Font glyph icons are wrong.
**Branch:** `add-sketchybar` (PR #58). Everything below is committed and pushed.

## The symptom

The bar renders literal six-character text `` / `` / ``
instead of glyphs. Confirmed from screenshots as **literal text, NOT tofu
boxes (▯)** — that distinction matters and was established late.

What works vs what doesn't:

| Item | Icon value | Result |
|---|---|---|
| `win.0` (app pill) | `:terminal:` — **plain ASCII** | renders correctly |
| clock / date / battery % | text labels | render correctly |
| `space.1..4` | U+F0B1 etc — **PUA codepoint** | literal `` text |
| `battery` icon, `apps` | U+F241, U+F179 — **PUA** | literal text |

The clean split is **ASCII renders, private-use-area codepoints don't**.
`sketchybar-app-font` works *because* it is a ligature font fed ASCII, so it
never asks sketchybar to handle a PUA character.

## RULED OUT (do not re-investigate)

Each of these was tested and is NOT the cause:

1. **Font missing the glyph.** `cmap` maps U+F0B1 to real glyph ids
   (JetBrainsMono 3783/4249, non-zero) with normal 9.60 advance, not `.notdef`.
2. **Font not registered.** `CTFontCreateWithName` round-trips the family
   name; `CTLineCreateWithAttributedString` renders the char with **no
   fallback** (run resolves to `JetBrainsMono Nerd Font Mono`, width 9.6).
3. **Nested nix font install.** Was real and worth fixing — `fonts.packages`
   buries `.ttf` six dirs deep under `/Library/Fonts/Nix Fonts/` where macOS
   does not scan. Switched to Homebrew casks (98 files flat in
   `~/Library/Fonts`). Did NOT fix the symptom.
4. **Wrong font family name.** nixpkgs and Homebrew BOTH report Family
   `JetBrainsMono NFM`, with the long name as typographic family (ID 16).
   Not a nixpkgs quirk. Both names resolve.
5. **A bad/unpatched font.** Swapped JetBrainsMono → Hack Nerd Font. Identical
   failure. Two independent fonts.
6. **Font Book disabled.** No `Disabled.collection` exists.
7. **Shell escape not expanding.** bash 3.2 (`/bin/bash`, what the agent
   resolves) expands `$''` to correct bytes `ef 82 b1`. Verified through
   the full array path.
8. **sketchybar receiving wrong data.** `--query` shows **one character**,
   U+F0B1 — not six. True after `--reload` too.
9. **Stale daemon / font cache.** Full `bootout`+`bootstrap`, plus a complete
   machine reboot. No change.
10. **Missing UTF-8 locale.** Was a real gap (launchd gives agents no LANG) and
    matches upstream #154/#176, so it is now set — `LANG`/`LC_ALL` =
    `en_US.UTF-8`, confirmed present in the *running* process env via
    `ps -p <pid> -Eww`. Did NOT fix the symptom. **Keep the fix; it is correct
    hygiene, just not the cause.**

## Upstream leads

- SketchyBar issue **#176** "Incorrect Unicode character rendering" — nearly
  identical symptom. Resolved there by re-patching the font variant, which
  option 5 above rules out for us.
- Maintainer states sketchybar's **built-in default font is Hack Nerd Font**,
  so an item with no font set should still render Nerd Font glyphs.
- Issue **#154** is the locale one.

## NEXT STEPS (untested, in priority order)

1. **Finish the label-vs-icon test.** Upstream #176 reported the char renders
   in a `label` but not an `icon`. I set that up but ran out of context before
   getting a visual answer. If **label renders and icon does not**, that is a
   sharp, reportable sketchybar bug and a usable workaround (move glyphs to
   labels).
2. **Test with sketchybar's bundled default font properly.** Our `--default`
   sets `icon.font`, so "unset" items still inherit JetBrainsMono. Need an item
   created before/outside that default, or explicitly `Hack Nerd Font`.
3. **Try a non-PUA unicode char** (e.g. `★` U+2605) in an icon. If that renders
   and PUA does not, the boundary is confirmed as PUA-specific.
4. **File upstream** with the ruled-out list — it is strong evidence.
5. **Workaround if abandoning:** replace glyph icons with ASCII text
   (`1 2 3 4`, `BAT`) or app-font ligature syntax. Bar becomes fully usable.

## Environment facts

- sketchybar **2.24.0** (Homebrew, `felixkratz/formulae`), `/opt/homebrew/bin/sketchybar`
- Agent: `org.nixos.sketchybar`; bridge: `org.nixos.sketchybar-bridge`
- Restart: `launchctl kickstart -k "gui/$(id -u)/org.nixos.sketchybar"`
- Fonts: Homebrew casks `font-jetbrains-mono-nerd-font`, `font-sketchybar-app-font`,
  `font-hack-nerd-font`. **Do not move back to `fonts.packages`** (see #3).
- Display 1512x982, notch left edge **663pt** (user-measured).
- `notch_width` only constrains CENTER-anchored items; left/right-anchored
  items flow past it. `WM_WIN_MAX=1` is what actually keeps the island clear.

## Other state on this branch

- OmniWM IPC is ON. `ipcEnabled = true` in settings.toml is NOT sufficient
  alone — "Enable IPC" must be clicked once in OmniWM's menu bar icon.
- Bar is 24px flush; `gaps.outer.top = 24` matches it.
- All 65 OmniWM hotkeys and workspaces `[💼 1, 2, 3, 4]` preserved throughout.
- Open PRs: **#58** (sketchybar), **#59** (soundsource), **#57** (ghostty opacity).
- CI red on `main` for 5+ runs, pre-existing: `flake.nix:62` uses
  `builtins.tryEval builtins.currentSystem`, which cannot catch a missing
  attribute. Fix is `builtins.currentSystem or "aarch64-darwin"`. Also removes
  the need for `--impure` on every rebuild.

## Gotcha that keeps biting

`homebrew.onActivation.cleanup = "uninstall"` means **rebuilding from a branch
that lacks a declaration uninstalls that software**. This removed OmniWM twice
and sketchybar once during this work. Merge PRs or merge locally before
rebuilding.

## Suggested ghostty change (not done)

`programs/ghostty.nix` has no `font-family`, so the terminal cannot render Nerd
Font glyphs. An earlier "do these render in your terminal?" test was therefore
**invalid** and briefly sent this investigation the wrong way. Setting
`font-family = JetBrainsMono Nerd Font Mono` would give a valid test surface.
