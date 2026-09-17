# Handoff: SketchyBar `\uf...` glyph bug

**Status:** WORKED AROUND (text icons). Root cause still unknown, but the
search space is now much smaller -- see "DECISIVE RESULT" below.
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

## DECISIVE RESULT (do this first if resuming)

Runtime-created probe items rendered the SAME codepoint U+F0B1, in the SAME
font, at the SAME 13pt size, as a **real briefcase glyph** -- confirmed by
screenshot. Tested and all worked:

  * as an `icon`, and as a `label`
  * at 13pt, 14pt and 16pt
  * right-anchored AND left-anchored
  * created via sketchybarrc's EXACT mechanism (bash array under /bin/bash,
    chained `--add --set`)
  * a non-PUA control (U+2605 star) also rendered

Meanwhile the four workspace pills sitting right next to those probes, same
font and size, still showed literal `\uf0b1` text.

**So sketchybar CAN render these characters on this machine.** Only items
created during config load fail. That kills the font, locale, PUA, shell,
icon-vs-label and anchor theories outright.

Extra clue from the user: a glyph appeared **briefly and then reverted**,
suggesting the icon is set correctly and then overwritten. `workspace.sh` only
touches `icon.color` and `background.*`, never `icon` -- so whatever overwrites
it has not been found yet. Worth instrumenting every `--set` the daemon issues.

Note `plugins/wm_prime.sh` is DEAD CODE here: it shells out to `wm status`
(kang's own multi-backend wrapper, absent in this setup), so `backend` is empty
and it exits early.

## CURRENT WORKAROUND

Workspace pills are plain digits 1-4; battery uses "+"/"!"; apps and meeting
icons are empty. No PUA codepoints are set from sketchybarrc. Bar is clean and
fully functional. To retry glyphs later, revert commit 0408fbe.

## NEXT STEPS (untested, in priority order)

1. **Find what overwrites the icon.** The glyph flashes then reverts. Log every
   `--set` the daemon issues (wrap the `sketchybar` binary in a logging shim on
   PATH, or `fs_usage`/`dtrace` the plugin invocations) and find who rewrites
   `space.N`'s icon after load.
2. **Bisect the load path.** Comment sketchybarrc down to just the four
   workspace items and reload. If they render, add back in halves until they
   break -- the culprit is whatever gets added last.
3. **Try setting the icons AFTER load.** Add a one-shot script that re-sets all
   glyph icons a second or two after startup. If that sticks, it is a load-order
   problem and that is also a clean permanent fix.
4. **File upstream** with the ruled-out list plus the decisive result -- the
   "works at runtime, fails at load" split is a strong, specific report.

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
