# Handoff — SketchyBar / OmniWM / performance session

Self-contained. Everything below was verified on this machine unless marked
otherwise.

## State at handoff

`main` = `c9fb972`, local checkout clean and synced.

| thing | state |
|---|---|
| sketchybar, borders, OmniWM | running, 0 log errors |
| window island | working (18 windows queried) |
| animated wallpaper | OFF via `features.wallspace` |
| terminal opacity | `1.0` (opaque) |
| Minecraft | installed |

## ONE PR STILL OPEN

**#74 — "Declare mpdecimal so Homebrew cleanup can actually run".** No
conflicts, one commit. Worktree at `.worktrees/brew-cleanup`.

This one matters: without it `cleanup = "uninstall"` aborts on `mpdecimal`
and **silently prunes nothing**, so the declarative guarantee is not actually
enforced. Merge it, then rebuild.

Merged this session: #70 (wallpaper flag), #72 (protocol diagnostic),
#73 (Minecraft).

## IN PROGRESS: hotkey to end a Tandem / Tuple call

The user asked about Hammerspoon for this. **Findings so far, all verified:**

- **Hammerspoon is NOT installed and NOT declared.** Do not assume it exists.
- **You probably do not need it.** `programs/karabiner.nix` already runs
  arbitrary shell from a hotkey — see the `shell_command` entries around
  line 142 that call `omniwmctl`. Same mechanism works here, with no new
  dependency and no new always-running agent.
- **Neither app is AppleScript-scriptable** (`NSAppleScriptEnabled` is false
  for both). So `tell application "Tuple" to end call` will not work.
- **Neither exposes a leave/end-call menu item.** Enumerated every menu of
  both apps' menu bars; the only relevant items are `Quit` / `Quit Tuple`.
  So GUI-scripting a menu click is out too.
- Both DO register URL schemes (`tandem:`, `tuple:`), but the verbs are
  undocumented — nothing found for hanging up. Worth probing before
  falling back.

**Therefore the realistic options, in order:**

1. **Keystroke simulation via System Events** to the frontmost app — find
   each app's native leave-call shortcut first, then send it. Least
   destructive.
2. **Quit the app** (`osascript -e 'quit app "Tuple"'`). Blunt but reliable;
   both apps reconnect fine.
3. Hammerspoon only if 1 and 2 both fail — and note it needs Accessibility
   permission, which MDM may gate.

**Not yet done:** identifying each app's actual in-call leave shortcut. That
is the next step, and it needs an ACTIVE CALL to test against.

Also noticed: **neither Tandem nor Tuple is declared in `darwin.nix`.** With
#74 merged and cleanup working, an undeclared *cask* gets removed on rebuild.
These were installed outside brew so they are currently unaffected, but
verify before assuming.

## Hard-won facts — do not re-derive

**`ps %cpu` is a LIFETIME AVERAGE.** It misled me three separate times this
session, including reporting Chrome at "111%" when it was averaging under 1%.
Always use cumulative CPU-time deltas:
`ps -o time= -p PID`, sleep, sample again, divide.

**This machine is too noisy for short A/B tests.** WindowServer swings 9–33%
on its own; Chrome spikes from idle to ~39% unpredictably. Three separate
opacity A/Bs were invalidated, one producing the physically impossible result
that *opaque* cost more than translucent. If you must A/B, hold Chrome
activity and window count fixed and sample for minutes, not seconds.

**Compositing cost comes from CHANGE, not layers.** JankyBorders runs 11
windows over 6.2× screen area; killing it changed WindowServer by nothing
measurable. The wallpaper was expensive because it forced 30 fresh composites
per second through everything above it — removing it took WindowServer ~27% →
~8-13% and load ~6.5 → ~1.8.

**cmux EMBEDS ghostty** and reads `~/.config/ghostty/config` directly. So
`pgrep ghostty` finds nothing while every cmux window honours that file. cmux
caches the config at WINDOW CREATION — config changes need a cmux restart,
and `SIGUSR2` does not work.

**`kCGWindowAlpha` is the whole-window multiplier, NOT per-pixel framebuffer
alpha.** It reads 1.0 on translucent cmux windows. To test whether something
shows through, sample screen pixels over time.

**nix-darwin normalises `homebrew.casks` into ATTRSETS with a `name` field**,
not plain strings. `builtins.elem "foo" casks` is always false and makes a
working gate look broken. Filter on `x.name == "foo"`.

**The flake reads the git tree.** A new file is invisible to Nix until
`git add`ed — activation silently no-ops.

**OmniWM ships `omniwmctl` INSIDE the .app bundle.** When the app updates on
disk while an old instance runs, the CLI jumps protocol versions immediately
and every query fails with `protocol_mismatch`. Fix is restarting OmniWM. PR
#72 added a log line naming this, because the old failure mode was a silently
blank island.

**`gaps.outer.top = 36`, not 32, is load-bearing.** The bar is 32pt; the
border stroke is centred on the window edge, so at a 32pt gap exactly
`width/2` paints inside the bar. `order=below` does NOT fix it — the bar is
absent from the CoreGraphics window list entirely.

**AppleScript cannot see recurring events whose series started before today.**
Calendar.app stores them with their ORIGINAL start date, so a
`whose start date` filter bounded to today never matches. A weekly standup
begun last month is invisible in the meeting item. **This bug is still
unfixed.** EventKit would handle it but is MDM-blocked.

## Known-unfixed

- The recurring-events bug above.
- CI is red on `main` for two pre-existing reasons: `graphite-cli` (upstream
  nixpkgs packaging bug, zero-size shell completion) and a `currentSystem`
  error. Neither is from this session's work. User has said CI does not matter.
- `archive/gcal-api-attempt` — local-only branch holding a discarded Google
  Calendar API rewrite (368 lines). User said to throw it away; archived
  instead so it is recoverable. Delete with `git branch -D` when confident.

## Working conventions

- **Use a worktree** (`.worktrees/<name>`). Other Claude sessions share this
  repo; I committed to the wrong branch once by working in the main checkout.
- **Rebase before pushing.** Another session merged VoiceInk mid-work and my
  branch silently proposed reverting 741 lines of it.
- **Never bare `git stash`** — the stack is shared across worktrees.
- `./install.sh` applies everything; it needs interactive sudo for the
  nix-darwin half, so a backgrounded run only completes the home-manager half.
