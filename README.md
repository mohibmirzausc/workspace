# workspace

Personal nix-darwin + home-manager flake for macOS (with a linux fallback
target used only by CI). Manages the whole machine: system defaults,
Homebrew casks, launchd/services, and every custom program below.

Single-user repo. PR titles read as an imperative-mood changelog on purpose —
`git log --oneline` is the changelog.

## Layout

```
flake.nix            entry point + feature flags + mkDarwin / mkHome
darwin.nix           system-level nix-darwin config (fonts, defaults, homebrew, users)
home.nix             user-level home-manager config; imports everything in programs/
install.sh           `darwin-rebuild switch` wrapper used by the `homeswitch` shell fn
overlays/            nixpkgs overlays (currently just claude-code)
programs/            one directory per managed program (see below)
docs/                design notes, reference docs, lessons learned
.github/workflows/   CI: builds both configs, weekly flake-lock bump PR
```

## Programs

Each `programs/<name>/` is either a `.nix` module imported by `home.nix`, or
a directory of source files consumed by a sibling `.nix` module, or both.

| Area                | Programs                                                                    |
|---------------------|-----------------------------------------------------------------------------|
| Window / UI stack   | `omniwm`, `borders` (JankyBorders), `sketchybar`, `hammerspoon`, `wallspace`|
| Terminal / mux      | `ghostty`, `cmux`, `tmux`, `zellij`                                         |
| Input               | `karabiner`, `linearmouse`, `voiceink`                                      |
| Agents (shared)     | `agents/` — skills + prompts symlinked into both Claude Code and Pi         |
| Claude-specific     | `claude/`, `claude-code-tools`, `claude-session.nix`                        |
| Dev workflow        | `just`, `git-worktree-switcher`, `worktree-tools`, `ticktick-sdk`, `sops`   |
| Misc                | `raycast`, `shottr`, `html-pages-server`, `yaks.nix`                        |

The interesting non-obvious ones:

- **`programs/agents/`** — one source-of-truth for skills and prompts,
  symlinked into `~/.claude/` and `~/.pi/agent/`. See
  `programs/agents/README.md` for the format contract (frontmatter is
  required or Pi silently skips the skill).
- **`programs/omniwm/`** — the custom tiling WM this repo drives. Sketchybar
  and JankyBorders read its state; Hammerspoon and Karabiner send it input.
- **`docs/lessons.md`** — reasons behind non-obvious past decisions, mined
  from commit messages so they don't rot in `git log`.

## Feature flags

`flake.nix` defines a single `features = { … }` attrset that is threaded to
every configuration. Flags are **hardcoded on purpose** — flipping one is a
config edit + rebuild, and the commit message is where the reasoning lives.
Do not promote them to `mkOption`s without reading that comment.

## Rebuild

```
homeswitch           # zsh function → sudo darwin-rebuild switch --flake ~/src/workspace
just switch          # equivalent, from any dir (global justfile)
just update          # nix flake update
just gc              # gc generations older than 14 days
```

`install.sh` is the same call, used on a fresh box. Do **not** run it with
`sudo`; it invokes sudo internally with the env passthrough Homebrew needs.

## CI

`.github/workflows/ci.yml` builds the darwin config on macOS and a
home-manager config on Linux, and runs `nix flake check --impure`, on every
push and PR to `main`.

`.github/workflows/update-flake.yml` runs weekly, bumps `flake.lock`, builds
all three configs, and opens a PR if anything changed.
