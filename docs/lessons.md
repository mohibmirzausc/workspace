# Lessons

Non-obvious findings from past work, surfaced from commit messages so they
don't rot in `git log`. Each entry: what we learned, and the commit(s) that
proved it. Append-only.

## WM / performance

- **Wallspace animated wallpaper cost ~50% CPU.** Wallspace + WindowServer
  measured ~54% combined against 4.7% for the same video benchmarked alone.
  Disabling took system load from ~6.5 to ~1.8. Now hidden behind the
  `wallspace` feature flag, off by default. — `8440ade`
- **JankyBorders uses ~2× the memory with `hidpi=on`.** Turning it off
  halved borders' RSS with no visible difference on this display. —
  `4055d23`
- **The window island got ~2.7× faster** after a targeted refactor that
  also fixed three log errors — worth profiling before assuming Swift/AppKit
  is the floor. — `b36f8a7`

## Tooling collisions

- **`minikube` ships its own `bin/kubectl` as of nixpkgs 26.11**, which
  collides with the standalone `kubectl` in `home.packages` and breaks
  `pkgs.buildEnv`. Fix: drop minikube's copy so the pinned kubectl wins.
  Comment lives in `home.nix` next to the package list. — see `home.nix`
- **`mpdecimal` must be declared** for Homebrew cleanup to actually run —
  otherwise every rebuild leaves it as an orphan and cleanup bails. —
  `5cbb2fd`

## Agent config

- **Pi silently skips a `SKILL.md` without `name`/`description` frontmatter.**
  Claude Code is lenient and lists it anyway, so a skill can work in one
  harness and be invisible in the other. Discovered via the `nelson` skill.
  CI now lints for this (`.github/workflows/lint-agents.yml`). — see
  `programs/agents/README.md`
- **Skills + prompts can be shared** between Claude Code and Pi via
  symlinks to `programs/agents/{skills,prompts}` — no format translation.
  Verified against pi 0.85.1 end-to-end (`/grill-me` expanded and ran). —
  `c7172c5`

## Triage / cmux

- **3 windows is the right threshold** to switch a workspace from dwindle
  to niri layout, not 5. Fewer than 3 is manageable dwindle; at 3+ the
  scrollable niri layout wins. — `5777312`
- **Triage must never close windows.** Unsure windows park on workspace 10
  ("review") instead. Undo/log every run so a bad triage is recoverable. —
  `5bd4af3`, `07db513`

## Meeting-leave hotkey

- **Different apps hide the "leave call" control in different places.**
  Meet's button "cannot be pressed" without clicking through its overlay;
  Tandem needs the in-call leave, not the room's; Tuple needs its own
  handler. One hotkey (Caps+H) — but per-app leave logic. — `fcbfe40`,
  `1ec939e`, `de69905`

<!--
Adding an entry: keep it to what future-you would want to know *before*
touching the same code. Link the commit(s) that proved the point. If a
lesson stops being true, don't delete — annotate with a superseding entry.
-->
