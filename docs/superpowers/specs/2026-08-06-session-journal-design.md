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
| `CLAUDE_CODE_SESSION_ID` | UUID | Session identity. Present in env, but **prefer the `session_id` field on the hook's stdin payload** — that is the documented contract, the scripts already parse stdin, and relying on an undocumented env var adds fragility for no gain. Use env only as a fallback. |
| `CMUX_AGENT_LAUNCH_CWD` | path | Workspace's original directory; stable even after `cd`. Better anchor than live `pwd`. |
| `CMUX_TERMINAL_LIFECYCLE_ID` | UUID | Distinct from the above; survives terminal restarts. |
| `CLAUDE_CODE_CHILD_SESSION` | `1` | **Unusable as a subagent discriminator** — cmux sets it on every session (already documented in `home.nix`). |
| `CMUX_CLAUDE_HOOK_CMUX_BIN` | path | cmux installs its own Claude hooks. Composition with ours is an open risk (R1). |

### Existing gallery server constraints

Read from `programs/html-pages-server/server.js` (607 lines). All satisfiable
**without modifying the server**:

1. **`.jsonl` is absent from the MIME table** (`server.js:468-475`; `.json` is
   present at `:471`) → an unknown extension serves as
   `application/octet-stream` (`server.js:489`).

2. **A recursive `fs.watch` over the whole root** (`server.js:544-549`) fires on
   any `.html|.css|.js|.mjs|.json` change, clears the entire metadata cache
   (`:546`), and after a 120 ms debounce broadcasts an SSE `reload` (`:539-541`)
   that triggers a full `location.reload()` in subscribed pages.

   These first two constraints **pull in opposite directions**: the extension
   that gets a correct MIME type is exactly the one that puts every append
   inside the watcher's filter. Resolution: name the data file **`entries.txt`**
   — `.txt` is the one extension that wins on *both* axes. It is **absent from
   the watcher regex** (so appends cause no cache clears and no reload
   broadcasts) while being **present in the MIME table** (`server.js:474`), so it
   serves as `text/plain; charset=utf-8`. Verified by evaluating the server's
   actual regex and MIME table against candidate filenames: `.json` fires the
   watcher; `.jsonl` and `.log` are quiet but serve as `application/octet-stream`;
   only `.txt` is quiet *and* correctly typed.

   (It holds JSON Lines despite the extension; the client splits on newlines.)

   Two corrections to an earlier draft of this spec, both verified against the
   source:
   - The claim that gallery metadata would "freeze permanently" because the
     cache keys on `index.html` mtime (`server.js:92-94`) was **wrong**. The
     watcher's `metaCache.clear()` already invalidates on any data write.
   - The prescribed fix — `touch index.html` after every append — was
     **actively harmful**: it would fire the watcher and reload every open tab
     on every append, across all workspaces. With many parallel sessions that is
     a reload storm, and it defeats the client-side polling this design relies
     on. Do not touch `index.html` after creation.

3. **Our journal page is immune to reload broadcasts.** The SSE subscription
   exists only in the server's *own generated* pages (`server.js:346`, `:460`).
   Our `index.html` is standalone and simply never opens an `EventSource`; it
   polls `entries.txt` instead. The gallery index page remains subscribed, which
   is why constraint 2's extension choice matters — it keeps journal appends
   from reloading the user's other open tabs.

4. **The gallery sorts date-desc off the `YYYY-MM-DD` folder prefix**
   (`server.js:152-153`), so a long-lived journal would sink as it ages. But
   `meta.json`'s `date` field *overrides* the folder prefix (`server.js:112`).
   **Fix:** write *last-updated* into `meta.json.date`, so active journals float
   to the top automatically.

   Accepted consequence: the folder name keeps its **creation** date while the
   displayed date is **last-updated**, so the two diverge over a long-lived
   journal. The displayed date is the one to trust. This also makes `/styles`
   first-seen/last-seen aggregation (`server.js:369-370`) report a moving point
   rather than a range for journals — acceptable, as `/styles` is for design
   experiments, not journals.

5. **A directory with no readable `index.html` is skipped entirely**
   (`server.js:145-147`) — it does not appear in the gallery and no error is
   surfaced anywhere. **`index.html` must therefore be written first**, before
   `entries.txt` or `meta.json`, or a journal can exist on disk while being
   invisible. See Phase 1 ordering.

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

Chosen: an append is **one line to `entries.txt`** — O(1) regardless of journal
length, with no read-back. `index.html` is a static shell written once that
fetches and renders the data, polling so an already-open tab updates itself.
Requires the 7777 server, which is already running.

> **AMENDED 2026-08-06 (implementation):** the `--static` regeneration fallback
> for `file://` was **dropped**. The gallery server is an always-on launchd
> agent, so `file://` is not a real access path; the page degrades gracefully
> there anyway (it renders and shows "offline" rather than breaking). Building a
> second rendering path for a case that does not occur is unjustified. If
> `file://` support is ever needed, add it then.

### Concurrency

Multiple panes and multiple subagents append to one file simultaneously, and
`meta.json` is updated by the same writers. The two paths have very different
risk profiles and get different treatment.

> **AMENDED 2026-08-06 (implementation):** `flock(1)` **does not exist on
> macOS**. Everywhere this section says `flock`, the implementation uses an
> atomic **`mkdir` mutex** (`mkdir(2)` is atomic on APFS) with the same
> semantics. Verified empirically: 8 concurrent writers × 40 entries → 320
> intact, distinct JSON lines. The lock is also bounded by **wall clock (2s)**
> rather than an iteration count — `sleep 0.001` cannot deliver 1 ms because
> process spawn dominates, so an iteration-capped loop stalled 18–26 s inside a
> per-turn hook.

**Appends to `entries.txt` — a real lock, not folklore.** An earlier draft claimed
these were "atomic (single `O_APPEND` write under the pipe-buffer limit)". That
justification was wrong on three counts and is retracted:

- `PIPE_BUF` (512 bytes on macOS) governs *pipes*, not regular files. Wrong
  constant, cited as though authoritative.
- POSIX guarantees only that `O_APPEND` makes the seek-and-write indivisible,
  not that a `write()` to a regular file is atomic at any size. Non-interleaving
  under the FS block size is an empirical property of APFS, not a standard.
- Decisively: the implementation is bash, and `printf '%s\n' "$x" >> f` does not
  reliably produce one `write(2)` syscall — a `jq` pipeline in between can split
  output regardless.

Therefore: **every append takes an exclusive `flock` on the journal directory's
lock file.** The critical section is one `printf` to an already-open fd, so
contention is microseconds even with many writers. Bodies are truncated to
**4096 bytes** at the CLI boundary — not for atomicity (flock handles that) but
to bound entry size so one runaway entry cannot dominate the page. Lines
exceeding it are truncated with a visible `…[truncated]` marker.

This supersedes R3's earlier "no locking" stance, which traded a real corruption
risk for an unmeasured latency saving.

**Updates to `meta.json` — the hazard that actually matters.** This is a
read-modify-write of a whole JSON file (date rollover, `session_ids` and
`pane_ids` accumulation) performed by multiple panes and subagents. A torn write
here fails *silently*: `readPageMeta` wraps the sidecar parse in `try/catch`
(`server.js:99-114`) and falls through to regex extraction, so a corrupted
`meta.json` degrades to title-only with no error anywhere. Mitigations:

- Take the **same `flock`** as the append path (one lock per journal covers both).
- **Write atomically**: serialize to `meta.json.tmp` in the same directory, then
  `mv` into place. `rename(2)` within a filesystem is atomic, so a reader never
  observes a partial file.
- **Update only on change**, not on every append: `session_ids`/`pane_ids` grow
  rarely, and `date` needs rewriting at most once per day. Skip the write when
  the content is unchanged — this also keeps `meta.json` (a `.json` file, and so
  *inside* the watcher's filter) from triggering reload broadcasts on every
  append.

Entries carry `pane_id`, `session_id`, and `agent` fields so interleaved streams
stay legible.

### Read path

Appending is O(1), but reads must be bounded too, since the file is never
pruned (requirement 8) and never rotated (requirement 7).

- **The agent does not read the journal to append.** Entries are write-only from
  the agent's perspective; no read-before-write, no dedup pass.
- **Resume reads `meta.json` only** (small, fixed size) to append a session id —
  never `entries.txt`.
- **`session-journal tail -n N`** exists for when the agent or user genuinely
  needs recent context; it reads the last N entries, defaulting to 20. Nothing
  in the normal path reads the whole file.
- The browser fetches the whole file, which is fine — it is the browser, and the
  page renders newest-first with older entries lazily revealed.

## Identity and layout

One journal per **workspace** (`CMUX_WORKSPACE_ID`), not per pane and not per
session. Panes and sessions interleave into the shared file, tagged. A single
folder persists for the workspace's whole life — no daily rotation.

```
~/html-pages/<YYYY-MM-DD>-session-<repo>-<branch>-<wsid8>/
  index.html      ← static shell, written once; NEVER touched afterwards
  entries.txt     ← JSON Lines, append-only (extension dodges the fs.watch filter)
  meta.json       ← gallery metadata; `date` = last-updated so it floats
  .lock/          ← mkdir-mutex directory for appends and meta updates
```

`<wsid8>` is the first 8 hex chars of `CMUX_WORKSPACE_ID` (e.g. `2d0cdddb`).
Without it the folder name carries nothing unique: two cmux workspaces on the
same repo *and* same branch created the same day — two panes exploring
alternatives, or a re-clone — would collide on an identical path and silently
merge into one journal, violating the one-journal-per-workspace rule. An earlier
draft claimed such workspaces "stay distinct via workspace id" while placing
that id only *inside* `meta.json`; nothing kept them distinct on disk. The
suffix fixes that at the cost of eight characters.

Fallback when `CMUX_WORKSPACE_ID` is unset (running outside cmux): derive an
8-char hash from `CMUX_AGENT_LAUNCH_CWD` (or `pwd`) so the scheme still yields a
stable, unique folder.

### Discovery: how an agent finds the right journal

Markers live in **two places**, because the two lookup paths have different
access:

1. **`meta.json`** — for filesystem lookup (`grep -l <uuid> ~/html-pages/*/meta.json`).
   Note that the server reads only `title/style/keywords/recreate/date` from the
   sidecar (`server.js:107-113`) and **silently discards** every marker field, so
   these are *not* visible over HTTP. Filesystem access is required for this path.

2. **`index.html` itself** — the user's requirement was that *the page* embed the
   markers. The static shell therefore carries them in a machine-readable block
   near the top, so an agent that fetches the page over HTTP (or greps the HTML
   directly) can identify it without reading the sidecar:

   ```html
   <meta name="session-journal:workspace-id" content="<uuid>">
   <meta name="session-journal:repo" content="workspace">
   <meta name="session-journal:branch" content="chore/upgrade-nixpkgs">
   <meta name="session-journal:cwd" content="/Users/mohib/src/workspace">
   <script type="application/json" id="sj-markers">{ …full marker object… }</script>
   ```

   Session and pane ids are *not* embedded in `index.html` — they accumulate over
   the journal's life and the shell is written once. They live in `meta.json` and
   in the `session` entries within `entries.txt`, both of which are appendable.
   An agent searching by session id greps `meta.json` or `entries.txt`; an agent
   searching by workspace/repo/branch can use either the page or the sidecar.

`meta.json` carries the full marker set:

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
of colliding: two parallel workspaces on the same repo stay distinct via the
`<wsid8>` folder suffix, while still being discoverable as siblings of one repo
through this field.

## Entry model

```json
{
  "ts": "<iso8601>",
  "kind": "decision|progress|blocker|milestone|question|files|commit|subagent|session",
  "source": "agent|hook|subagent",
  "title": "one line",
  "body": "optional, markdown, truncated at 4096 bytes to bound entry size",
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

**User prompts** are recorded as a truncated first line (~120 chars) by a
`UserPromptSubmit` hook, with an empty body — an index of what a session was
doing, not an archive of the conversation. Noted for awareness: these
land in `~/html-pages/` in plaintext, and the user works on client repos.

## Enable flag

Env var overrides state file (option C), following the existing `beep-state`
convention so the mechanism is already familiar:

1. `SESSION_JOURNAL=0` — hard off, regardless of anything else.
2. `SESSION_JOURNAL=1` — hard on.
3. Per-repo `.session-journal` / `.no-session-journal` in the repo root.
4. **`~/.claude/session-journal-state`** containing `ENABLED` or `DISABLED` —
   the global default, mirroring `~/.claude/beep-state`.
5. Default when the state file is absent: **`DISABLED`** (opt-in), written on
   first read so the file always exists afterwards. Installing the hooks changes
   nothing until deliberately enabled.

The check lives **in the hook script**, which exits 0 immediately when disabled.
"Stop journaling" is therefore enforced by the harness rather than honored by
the model, and takes effect mid-session.

Shell helpers mirror the existing `claude-beep-*` functions in `home.nix`:
`claude-journal-on`, `claude-journal-off`, `claude-journal-status`.

### The state file must be a mutable copy, not a symlink

`beep-state` is installed via `home.file` with `force = true` (`home.nix:139-142`),
which makes `~/.claude/beep-state` a **symlink into the nix store**. The existing
`claude-beep-mute` helper does `echo "DISABLED" > ~/.claude/beep-state`, writing
*through* the symlink into a read-only store path — so that toggle either fails
outright or is silently reverted by the next `homeswitch`. (Pre-existing bug in
the beep toggle, noted here because copying the pattern verbatim would inherit it.)

`session-journal-state` therefore uses the **mutable-copy** technique already
present in this repo for LinearMouse (`home.activation.installLinearMouseConfig`):
seed the file from a repo-tracked default on first install, never overwrite an
existing one. Same location and convention as `beep-state`, but the toggle
actually persists.

Requirement 5 ("config lives in `programs/claude/`") is satisfied for everything
version-controlled: hooks, skill, CLI, and the *seed* for the state file all live
there. The live state file itself is necessarily mutable runtime state under
`~/.claude/` — the same category `programs/claude/README.md` already documents as
"not version controlled". An earlier draft asserted "everything lives under
`programs/claude/`" while placing the toggle at `~/.config/session-journal/`;
that claim was false and the location is now consistent with the rest of the setup.

## Lifecycle

No explicit end state. When a session ends it simply stops appending, and the
journal remains in whatever state it reached. Staleness is conveyed by
time-since-update in the gallery. A reopened task resumes appending to the same
file.

## File layout in this repo

All version-controlled pieces live under `programs/claude/`, consistent with the
existing nix-managed setup (`home.nix:135-155` symlinks these into `~/.claude/`):

```
programs/claude/
  settings.json                     ← register hooks (APPEND to arrays — see below)
  session-journal-state             ← seed for the mutable state file (ENABLED/DISABLED)
  hooks/
    session-journal-start.sh        ← SessionStart: open/attach + inject context
    session-journal-tool.sh         ← PostToolUse: coalesce edits, catch commits
    session-journal-subagent.sh     ← SubagentStop: harvest the final report
    session-journal-stop.sh         ← Stop: flush turn, run nudge check
    lib/session-journal-common.sh   ← flag check, identity resolution, locked append
  skills/session-journal/
    SKILL.md                        ← Tier-2 guidance for the agent
```

Mutable runtime state (not version-controlled, consistent with the "What's Not
Here" section of `programs/claude/README.md`):

```
~/.claude/session-journal-state              ← ENABLED/DISABLED toggle (mutable copy)
~/.claude/session-journal/<wsid8>/turn.json  ← per-turn coalescing buffer + nudge bookkeeping
~/html-pages/<...>/                          ← the journals themselves
```

The per-turn buffer needs a writable scratch path because `PostToolUse`
accumulates file edits that `Stop` then flushes as one coalesced entry; it is
keyed by `<wsid8>` so parallel workspaces never share a buffer, and cleared at
each flush.

The `session-journal` CLI is packaged like the existing
`programs/claude-code-tools/` entries so it lands on `PATH` via home-manager.

### Registering hooks without breaking what is already there

Two hazards, both verified in the current `settings.json`:

1. **A `Stop` hook already exists** (`settings.json:17-26`) — `tool-after.sh`,
   the beep, registered with no matcher. Our `Stop` hook must be **appended to
   that array**, not written over it. A literal reading of "register hooks"
   silently kills the user's beep.
2. **`settings.json` is symlinked read-only from the nix store**
   (`home.nix:135-138`, `force = true`), and `README.md` documents that runtime
   mutation fails with `EACCES`. Hook registration is therefore a **`homeswitch`
   operation**, not a live edit. This is also why the enable flag is a separate
   mutable file rather than a settings key — the flag must be toggleable
   mid-session, and `settings.json` cannot be.

The existing file only demonstrates single-string matchers (`"AskUserQuestion"`,
`settings.json:8`). The `PostToolUse` matcher `Edit|Write` uses regex-alternation
syntax that is **not** exercised anywhere in this config; Phase 1 must verify it
matches as intended rather than assume it, falling back to two separate matcher
entries if not.

### Implementation language

**bash + `jq`**, matching the existing hooks (`tool-after.sh`, `statusline.sh`)
— both already on `PATH` with no new runtime dependency, and fast to start,
which matters because `Stop` and `PostToolUse` add latency to every turn.

Correcting an earlier draft: this does *not* "match the html-page skill's
approach". `html-page` has no implementation language — it is a `SKILL.md` that
instructs the model to author HTML, and the server backing it is zero-dependency
**Node**. Node is therefore the closest precedent for a shipped tool in this
repo. bash is still the right choice here on hook-latency grounds, but the
earlier justification was fabricated and the tradeoff is stated plainly instead.
If the HTML renderer grows beyond what bash comfortably templates, moving *only*
the `init` path (which runs once per journal, not per append) to Node is
acceptable; hooks stay bash.

## Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | cmux installs its own Claude hooks (`CMUX_CLAUDE_HOOK_CMUX_BIN`); ours may be clobbered or may clobber cmux's. | Verify composition in Phase 1 before building on top. Fallback: chain from cmux's hook rather than registering separately. |
| R2 | `CLAUDE_CODE_CHILD_SESSION` cannot identify subagents in this setup. | Use the `SubagentStop` hook itself as the discriminator plus its stdin payload; never infer from that env var. |
| R3 | Hook latency on every turn across many parallel sessions. | Scripts do one locked append and exit; no model calls, no network. `flock` critical section is a single `printf` to an open fd — microseconds. (Supersedes this row's earlier "no locking" stance, which traded real corruption risk for an unmeasured saving.) |
| R4 | Model forgets Tier-2 entries under long context. | Three reinforcing mechanisms (injection, skill, nudge) plus a Tier-1 floor that keeps the journal useful regardless. |
| R5 | Prompt text and reasoning stored in plaintext for client work. | Flagged for the user; opt-in default and per-repo `.no-session-journal` provide control. |
| R6 | Gallery pollution — journals mixed with design pages. | Reserved `session-` slug prefix makes them searchable and visually grouped; `style: "Session journal"` distinguishes them. |
| R7 | `/styles` encyclopedia pollution — every journal shares `style: "Session journal"`, and `/styles` sorts by count desc (`server.js:375-376`), so journals would outrank the user's actual design experiments. | Accepted for now; journals are expected to outnumber pages. If it becomes annoying, the fix is a one-line server filter excluding `kind: "session-journal"` from `/styles` — deliberately deferred to avoid modifying the server in this project. |
| R8 | Reload storm — appends triggering SSE broadcasts that reload every open tab. | `entries.txt` sits outside the watcher's `html\|css\|js\|mjs\|json` filter (`server.js:545`); `index.html` is never touched after creation; `meta.json` is written only on actual change. |
| R9 | Torn `meta.json` from concurrent read-modify-write, failing silently into title-only extraction. | Shared `flock` + write-to-`.tmp`-then-`rename(2)`. See Concurrency. |
| R10 | A journal directory whose `index.html` is missing or unreadable is skipped by the gallery with no error anywhere (`server.js:145-147`). | `index.html` is written **first** at init, before `entries.txt` or `meta.json`; Phase 1 verification explicitly includes "appears in the gallery". |
| R11 | The existing `Stop` beep hook is silently destroyed by careless hook registration. | Append to the existing array; verify the beep still fires as a Phase 3 acceptance check. |

## Implementation phases

### Phase 1 — walking skeleton (validates the risky assumptions)

The risk in this project is not the HTML; it is whether hooks fire where we
expect and whether cmux's hooks interfere. Prove that before building
presentation on top.

1. `lib/session-journal-common.sh`: flag check, identity resolution (`<wsid8>`),
   `flock`-guarded append.
2. `session-journal` CLI with `init`, `add`, `tail`.
   `init` writes **`index.html` first** (R10), then `entries.txt`, then `meta.json`.
3. `SessionStart` + `SubagentStop` hooks only.
4. Plain unstyled `index.html` that fetches and dumps `entries.txt`.
5. **Verify against real parallel sessions:**
   - hooks fire at all, and compose with cmux's own hooks (R1)
   - subagent harvesting works; capture the real `SubagentStop` stdin schema (R2)
   - the journal **appears in the gallery** at localhost:7777 (R10)
   - concurrent appends from 2+ panes and several subagents do not corrupt —
     write N entries from parallel writers and assert N valid JSON lines
   - appending does **not** reload other open gallery tabs (R8)

**Gate:** do not proceed until R1, R2, R8, and the concurrency check are settled
with evidence.

### Phase 2 — full capture

6. `PostToolUse` coalescing (per-turn buffer) and commit detection. Verify the
   `Edit|Write` matcher syntax actually works; fall back to separate entries if not.
7. `Stop` flush and nudge check.
8. `meta.json` maintenance: `date` rollover, `session_ids`/`pane_ids`
   accumulation — via `flock` + tmp-and-rename, written only on change.
   **No `index.html` touch** (R8).

### Phase 3 — presentation and guidance

9. Designed `index.html`: scannable timeline, source-distinguished entries,
   embedded discovery markers, live poll, filter by kind/pane/session.
10. `SKILL.md` for Tier-2 authoring.
11. Nix wiring: CLI package entry, `session-journal-state` mutable-copy
    activation, `claude-journal-*` shell helpers, and `settings.json` hook
    registration **appended** to existing arrays.
    **Acceptance check: the existing beep still fires** (R11).
12. Docs in `programs/claude/README.md`.

## Open items deferred to implementation

- Exact `SubagentStop` stdin schema (read at runtime in Phase 1 rather than
  assumed).
- Poll interval for the live page (start at 3s, tune once real journals exist).

### Not deferred: the `Stop` nudge

An earlier draft deferred "whether the nudge is worth its false-positive rate;
drop it if noisy". That had it both ways — the nudge is one of three mechanisms
carrying requirement 12 ("must not depend on the model remembering"), so
silently dropping it would remove a third of that mitigation without review.

Resolution: **the nudge ships**, and tuning is limited to its *threshold*, not
its existence. It fires at most once per turn, only when a turn produced
substantive changes (an edit or a commit) and no Tier-2 entry was written. If it
proves noisy, raise the threshold (e.g. only after N such turns) rather than
removing it. Removing it entirely is a design change requiring a spec revision.
