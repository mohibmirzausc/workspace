# Session Journal — Design

**Status:** approved design, pre-implementation
**Date:** 2026-08-06
**Repo:** `~/src/workspace` (nix dotfiles)

## Problem

The user runs many cmux workspaces in parallel, each with a Claude Code session.
Tracking what each session is doing requires reading agentic logs, which are far
too verbose to monitor across many sessions at once.

More precisely — and this is the framing that drives the whole design — the goal
is **not** an activity log. It is to preserve **the reasoning that scrolls out of
the chat**, so the human can review a session later and question the agent about
decisions it made. A bare "edited `foo.ts`" is worthless for that. "Chose X over
Y because Z" is the product.

Two consequences follow:

1. The valuable entries are **semantic** (judgment, decisions, blockers).
   Mechanical file-op entries are supporting texture only.
2. Semantic entries can only be produced by a model, so the design cannot rely
   on hooks alone — but it must not *depend* on the model either, since the user
   cannot instruct dozens of parallel sessions by hand.

Subagents must also contribute, and subagents skip skills by design.

## Goals

- One HTML file per cmux workspace, readable at a glance, served from the
  existing gallery at `localhost:7777`.
- Entries accumulate without the human prompting for them.
- Subagent work is captured without instructing subagents.
- Deterministic on/off that genuinely works, including mid-session.
- Cheap: appending must not cost tokens proportional to journal length.
- Findable: an agent must be able to locate the right journal from the pile.

## Non-goals

- Auto-deletion, pruning, or retention policy (explicitly declined).
- Replacing the agentic logs; this is a summary layer, not an archive.
- Per-turn LLM summarization (rejected on cost — it would bill every turn across
  many parallel sessions and add latency to every stop).
- Rotating visual styles per page (that is `html-page`'s job; a dashboard the
  user scans repeatedly must look the same every time).

## Environment findings

Verified by inspecting a live cmux session (2026-08-06):

| Variable | Value shape | Use |
|---|---|---|
| `CMUX_WORKSPACE_ID` | UUID | **Primary key.** Identical to `CMUX_TAB_ID` — a workspace *is* a tab. |
| `CMUX_PANEL_ID` / `CMUX_SURFACE_ID` | UUID (equal to each other) | Pane within the tab. One workspace can hold several concurrent Claude sessions via `cmd+d` splits. |
| `CLAUDE_CODE_SESSION_ID` | UUID | Session identity, readable directly from env — no stdin parsing needed. |
| `CMUX_AGENT_LAUNCH_CWD` | path | Workspace's original directory; stable even after `cd`. Better anchor than live `pwd`. |
| `CMUX_TERMINAL_LIFECYCLE_ID` | UUID | Distinct from the above; survives terminal restarts. |
| `CLAUDE_CODE_CHILD_SESSION` | `1` | **Unusable as a subagent discriminator** — cmux sets it on every session (already documented in `home.nix`). |
| `CMUX_CLAUDE_HOOK_CMUX_BIN` | path | cmux installs its own Claude hooks. Composition with ours is an open risk (R1). |

### Existing gallery server constraints

Read from `programs/html-pages-server/server.js` (606 lines). Three constraints,
all satisfiable **without modifying the server**:

1. **`.jsonl` is absent from the MIME table** → would serve as
   `application/octet-stream`. Therefore the data file is named
   **`entries.json`**, which is in the table and gets a correct content type.
   (It holds JSON Lines despite the extension; the client splits on newlines.)
2. **The metadata cache keys on `index.html` mtime** (`server.js:92-94`). Our
   `index.html` is written once and never edited, so gallery metadata would
   freeze permanently. **Fix:** the append script `touch`es `index.html` after
   every write, invalidating the cache.
3. **The gallery sorts date-desc off the `YYYY-MM-DD` folder prefix**
   (`server.js:152`), so a long-lived journal would sink as it ages. But
   `meta.json` supports a `date` field that *overrides* the folder prefix
   (`server.js:112`). **Fix:** write *last-updated* into `meta.json.date`, so
   active journals float to the top automatically.

## Architecture

Two tiers, deliberately layered so the system degrades gracefully.

### Tier 1 — deterministic floor (hooks)

Hooks are shell commands the harness runs, not text handed to the model. They
receive JSON on stdin and cannot be forgotten, skipped, or deprioritized. They
guarantee the journal is never empty and never stale:

- `SessionStart` — open/attach the workspace journal; record session id, pane
  id, cwd, branch, resume-vs-fresh.
- `PostToolUse` on `Edit|Write` — record touched files (coalesced, see below).
- `PostToolUse` on `Bash` — record git commits only, not every command.
- `SubagentStop` — **the key mechanism for the subagent requirement.** The hook
  receives the subagent's transcript; its final report is already a summary.
  Harvesting it here needs zero cooperation from the subagent, which is the only
  approach that actually holds given subagents skip skills.
- `Stop` — close out the turn; run the nudge check (below).

### Tier 2 — semantic layer (model-authored)

The entries the user actually wants. Produced by the agent calling the CLI:

```
session-journal add --kind decision --title "..." --body "..."
```

Reliability comes from three reinforcing mechanisms, none of which requires the
human to instruct anything:

1. **`SessionStart` context injection.** The hook returns `additionalContext`,
   which the harness prepends into the model's context. This is the same
   mechanism that delivers the superpowers banner — demonstrably effective.
2. **The skill file**, invoked normally when relevant.
3. **`Stop`-hook nudge.** If a turn produced substantive changes (edits, commits)
   but no Tier-2 entry, inject a reminder. This is the backstop against context
   drift on long sessions.

If Tier 2 fails entirely, Tier 1 still yields a usable timeline. That graceful
degradation is the point of the split.

### Write mechanism

**Append-only JSONL + client-side render.**

Considered and rejected:
- *Agent edits the HTML directly* — token cost grows linearly with journal
  length (a long session re-reads a large file on every entry), and concurrent
  subagents corrupt it. This is also what asking `html-page` to "append" would
  do today: it has no append path, only one-shot generation.
- *Script regenerates static HTML per append* — safe, `file://`-compatible, but
  heavier per write.

Chosen: an append is **one line to `entries.json`** — O(1) regardless of journal
length, atomic under concurrency (single `O_APPEND` write under the pipe-buffer
limit), no read-back. `index.html` is a static shell written once that fetches
and renders the data, polling so an already-open tab updates itself. Requires the
7777 server, which is already running. A `--static` regeneration fallback is
retained for `file://` use.

### Concurrency

Multiple panes and multiple subagents append to one file simultaneously. Each
entry is a single line written with `O_APPEND` and kept under the atomic-write
threshold; long bodies are truncated at the CLI boundary to preserve atomicity.
Entries carry `pane_id` and `agent` fields so interleaved streams stay legible.

## Identity and layout

One journal per **workspace** (`CMUX_WORKSPACE_ID`), not per pane and not per
session. Panes and sessions interleave into the shared file, tagged. A single
folder persists for the workspace's whole life — no daily rotation.

```
~/html-pages/<YYYY-MM-DD>-session-<repo>-<branch>/
  index.html      ← static shell, written once, touch()ed to bust the cache
  entries.json    ← JSON Lines, append-only
  meta.json       ← gallery metadata; `date` = last-updated so it floats
```

`meta.json` carries the discovery markers so an agent can find the right journal
by grepping rather than parsing folder names:

```json
{
  "kind": "session-journal",
  "title": "workspace · chore/upgrade-nixpkgs",
  "style": "Session journal",
  "date": "<last-updated YYYY-MM-DD>",
  "cmux_workspace_id": "<uuid>",
  "session_ids": ["<uuid>", "..."],
  "pane_ids": ["<uuid>", "..."],
  "cwd": "/Users/mohib/src/workspace",
  "launch_cwd": "<CMUX_AGENT_LAUNCH_CWD>",
  "repo": "workspace",
  "branch": "chore/upgrade-nixpkgs",
  "git_common_dir": "<resolved main repo, so worktrees group>",
  "started": "<iso>",
  "updated": "<iso>"
}
```

`session_ids` is plural because `autoResumeAgentSessions = true` means a
workspace's journal outlives any single session UUID; a resume appends its UUID
rather than orphaning the file. This makes "find the journal for session X" work
for any session that ever ran in the workspace.

`git_common_dir` is recorded so heavy `.worktrees/` use groups correctly instead
of colliding: two parallel workspaces on the same repo stay distinct via
workspace id, while still being discoverable as siblings of one repo.

## Entry model

```json
{
  "ts": "<iso8601>",
  "kind": "decision|progress|blocker|milestone|question|files|commit|subagent|session",
  "source": "agent|hook|subagent",
  "title": "one line",
  "body": "optional, markdown, truncated to keep the write atomic",
  "session_id": "<uuid>",
  "pane_id": "<uuid>",
  "agent": "main|<subagent type>"
}
```

Entries are visually distinguished by `source` so the human can tell
model-authored reasoning from mechanically harvested facts at a glance.

**Granularity:** file operations are **coalesced per turn** ("touched 6 files:
a.ts, b.ts, …") rather than logged individually — a refactor would otherwise
produce hundreds of lines and bury the reasoning that is the actual point.

**User prompts** are recorded as a truncated first line (~120 chars). They are
the best available index of what a session was doing. Noted for awareness: these
land in `~/html-pages/` in plaintext, and the user works on client repos.

## Enable flag

Env var overrides marker files (option C):

1. `SESSION_JOURNAL=0` — hard off, regardless of anything else.
2. `SESSION_JOURNAL=1` — hard on.
3. Per-repo `.session-journal` / `.no-session-journal` in the repo root.
4. Global `~/.config/session-journal/enabled`.
5. Default when nothing is set: **off** (opt-in), so installing the hooks
   changes nothing until deliberately enabled.

The check lives **in the hook script**, which exits 0 immediately when disabled.
"Stop journaling" is therefore genuinely enforced by the harness rather than
honored by the model, and it takes effect mid-session on a single `rm`.

## Lifecycle

No explicit end state. When a session ends it simply stops appending, and the
journal remains in whatever state it reached. Staleness is conveyed by
time-since-update in the gallery. A reopened task resumes appending to the same
file.

## File layout in this repo

Everything lives under `programs/claude/`, consistent with the existing
nix-managed setup (`home.nix` symlinks these into `~/.claude/`):

```
programs/claude/
  settings.json                     ← register hooks (edit)
  hooks/
    session-journal-start.sh        ← SessionStart: open/attach + inject context
    session-journal-tool.sh         ← PostToolUse: coalesce edits, catch commits
    session-journal-subagent.sh     ← SubagentStop: harvest the final report
    session-journal-stop.sh         ← Stop: flush turn, run nudge check
    lib/session-journal-common.sh   ← flag check, identity resolution, append
  skills/session-journal/
    SKILL.md                        ← Tier-2 guidance for the agent
```

The `session-journal` CLI is packaged like the existing
`programs/claude-code-tools/` entries so it lands on `PATH` via home-manager.

Implementation language is **bash + `jq`**, matching the existing hooks and the
`html-page` skill's approach; both are already on `PATH` with no new runtime
dependency. Hook scripts must stay fast — append a line and exit, no model calls
and no network — because `Stop` and `PostToolUse` add latency to every turn.

## Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | cmux installs its own Claude hooks (`CMUX_CLAUDE_HOOK_CMUX_BIN`); ours may be clobbered or may clobber cmux's. | Verify composition in Phase 1 before building on top. Fallback: chain from cmux's hook rather than registering separately. |
| R2 | `CLAUDE_CODE_CHILD_SESSION` cannot identify subagents in this setup. | Use the `SubagentStop` hook itself as the discriminator plus its stdin payload; never infer from that env var. |
| R3 | Hook latency on every turn across many parallel sessions. | Scripts do one append and exit; no model calls, no network, no locking. |
| R4 | Model forgets Tier-2 entries under long context. | Three reinforcing mechanisms (injection, skill, nudge) plus a Tier-1 floor that keeps the journal useful regardless. |
| R5 | Prompt text and reasoning stored in plaintext for client work. | Flagged for the user; opt-in default and per-repo `.no-session-journal` provide control. |
| R6 | Gallery pollution — journals mixed with design pages. | Reserved `session-` slug prefix makes them searchable and visually grouped; `style: "Session journal"` distinguishes them. |

## Implementation phases

### Phase 1 — walking skeleton (validates the risky assumptions)

The risk in this project is not the HTML; it is whether hooks fire where we
expect and whether cmux's hooks interfere. Prove that before building
presentation on top.

1. `lib/session-journal-common.sh`: flag check, identity resolution, atomic append.
2. `session-journal` CLI with `add` and `init`.
3. `SessionStart` + `SubagentStop` hooks only.
4. Plain unstyled `index.html` that fetches and dumps `entries.json`.
5. **Verify against real parallel sessions:** hooks fire, cmux composition is
   sane (R1), subagent harvesting works (R2), concurrent appends do not corrupt.

**Gate:** do not proceed until R1 and R2 are settled with evidence.

### Phase 2 — full capture

6. `PostToolUse` coalescing and commit detection.
7. `Stop` flush and nudge check.
8. `meta.json` maintenance: `date` rollover, `session_ids` accumulation,
   `index.html` touch.

### Phase 3 — presentation and guidance

9. Designed `index.html`: scannable timeline, source-distinguished entries,
   live poll, filter by kind/pane/session.
10. `SKILL.md` for Tier-2 authoring.
11. Nix wiring (`home.nix` package entry, `settings.json` hook registration).
12. Docs in `programs/claude/README.md`.

## Open items deferred to implementation

- Exact `SubagentStop` stdin schema (read at runtime in Phase 1 rather than
  assumed).
- Whether the `Stop` nudge is worth its false-positive rate; drop it if noisy.
- Poll interval for the live page (start at 3s, tune once real journals exist).
