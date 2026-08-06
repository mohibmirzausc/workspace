# Session Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every cmux workspace one HTML page, served by the existing localhost:7777 gallery, that accumulates the session's decisions and progress — written by hooks (which cannot forget) and by the agent (which supplies the reasoning), including from subagents.

**Architecture:** A bash CLI (`session-journal`) owns a per-workspace directory under `~/html-pages/`. Appends are single JSON lines to `entries.txt`, guarded by a `mkdir` mutex. A static `index.html`, written once at init, polls that file and renders it. Claude Code hooks call the CLI at `SessionStart`, `PostToolUse`, `SubagentStop`, and `Stop`, so capture does not depend on the model remembering. A skill instructs the model to add the semantic entries hooks cannot produce.

**Tech Stack:** bash + `jq` (both already on PATH; matches existing hooks), vanilla JS in the page, Nix home-manager for installation, `bats`-style plain-bash test scripts (no new dependency).

**Spec:** `docs/superpowers/specs/2026-08-06-session-journal-design.md`

---

## Context for someone with zero background

**What cmux is:** a macOS terminal that runs many AI coding agents in parallel, each in a "workspace" (a tab). The user may have a dozen open at once. Each workspace exports `CMUX_WORKSPACE_ID`.

**What Claude Code hooks are:** shell commands the Claude Code harness runs at lifecycle points. They receive a JSON payload on **stdin** and can return JSON on **stdout**. They are not instructions to the model — the harness executes them — which is why they are the reliable half of this design. Registered in `~/.claude/settings.json`.

**What the gallery is:** `programs/html-pages-server/server.js`, a zero-dependency Node server on port 7777 that scans `~/html-pages/*/index.html` on every request and renders a catalog. Already running as a launchd agent.

**How this repo installs things:** it is a Nix flake (nix-darwin + home-manager). Files in `programs/claude/` are symlinked into `~/.claude/` by `home.nix`. Applying changes = `homeswitch` (an alias for the darwin-rebuild command). **`~/.claude/settings.json` is a read-only symlink into the nix store** — never edit it at runtime.

**Critical constraints discovered during design (do not rediscover the hard way):**

1. `flock` **does not exist on macOS.** Use the `mkdir` mutex in `lib/session-journal-common.sh`. (Verified: 8 concurrent writers × 60 entries → 480 valid lines.)
2. The gallery server has a **recursive `fs.watch`** (`server.js:544-549`) that fires on `.html|.css|.js|.mjs|.json` changes and broadcasts an SSE reload to every open tab. The data file is therefore **`entries.txt`** — the only extension that is both outside that filter and inside the MIME table. **Never `touch index.html` after creating it.**
3. A journal directory whose `index.html` is missing is **silently skipped** by the gallery (`server.js:145-147`). Write `index.html` FIRST.
4. `settings.json` already has a `Stop` hook (the beep, `tool-after.sh`). **Append to that array; do not replace it.**
5. `CLAUDE_CODE_CHILD_SESSION=1` is set on *every* cmux session, so it cannot identify subagents.

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `programs/claude/hooks/lib/session-journal-common.sh` | Sourced library: enable check, identity resolution, mutex, append, meta update. The only file that touches the journal directory. |
| `programs/claude/hooks/lib/journal-template.html` | The static page shell. Separate from bash so the HTML is editable as HTML. |
| `programs/claude/hooks/session-journal` | CLI: `init`, `add`, `tail`, `path`, `status`. |
| `programs/claude/hooks/session-journal-start.sh` | `SessionStart` hook. |
| `programs/claude/hooks/session-journal-tool.sh` | `PostToolUse` hook. |
| `programs/claude/hooks/session-journal-subagent.sh` | `SubagentStop` hook. |
| `programs/claude/hooks/session-journal-stop.sh` | `Stop` hook. |
| `programs/claude/session-journal-state` | Seed for the mutable toggle (`DISABLED`). |
| `programs/claude/skills/session-journal/SKILL.md` | Tier-2 guidance for the model. |
| `tests/session-journal/run-tests.sh` | Plain-bash test runner. |
| `tests/session-journal/test-*.sh` | Individual test files. |

**Modified files:**

| Path | Change |
|---|---|
| `programs/claude/settings.json` | Register 4 hooks; append to the existing `Stop` array. |
| `home.nix` | Mutable-copy activation for the state file; `claude-journal-*` shell helpers. |
| `programs/claude/README.md` | Document the feature. |

**Why this split:** `session-journal-common.sh` is the single point of contact with the journal on disk, so concurrency and path logic live in exactly one place and the four hook scripts stay thin (parse stdin → call the CLI). The HTML template is a separate file so it can be edited and linted as HTML rather than escaped inside a heredoc.

---

## Task 1: Test harness and enable-flag logic

**Files:**
- Create: `tests/session-journal/run-tests.sh`
- Create: `tests/session-journal/test-enabled.sh`
- Create: `programs/claude/hooks/lib/session-journal-common.sh`

- [ ] **Step 1: Write the test runner**

```bash
#!/usr/bin/env bash
# tests/session-journal/run-tests.sh — runs every test-*.sh, reports pass/fail.
set -uo pipefail
cd "$(dirname "$0")"
pass=0; fail=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  out=$(bash "$t" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then pass=$((pass+1)); printf '  ok   %s\n' "$t"
  else fail=$((fail+1)); printf '  FAIL %s\n%s\n' "$t" "$out"; fi
done
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Also create a shared assertion helper at `tests/session-journal/assert.sh`:

```bash
#!/usr/bin/env bash
# Minimal assertions. Each test sets up an isolated HOME so nothing touches real data.
setup_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX"
  export SJ_PAGES_DIR="$SANDBOX/html-pages"
  mkdir -p "$HOME/.claude" "$SJ_PAGES_DIR"
  export CMUX_WORKSPACE_ID="11111111-2222-3333-4444-555555555555"
  export CMUX_AGENT_LAUNCH_CWD="$SANDBOX/repo"
  mkdir -p "$CMUX_AGENT_LAUNCH_CWD"
  unset SESSION_JOURNAL
}
teardown_sandbox() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
assert_eq() {
  if [ "$1" != "$2" ]; then echo "assert_eq failed: expected [$2] got [$1] ${3:-}"; exit 1; fi
}
assert_contains() {
  case "$1" in *"$2"*) ;; *) echo "assert_contains failed: [$1] lacks [$2] ${3:-}"; exit 1;; esac
}
assert_file_exists() { [ -f "$1" ] || { echo "missing file: $1 ${2:-}"; exit 1; }; }
```

Note `SJ_PAGES_DIR`: the library must honor this override so tests never write to the real `~/html-pages`.

- [ ] **Step 2: Write the failing test for the enable flag**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-enabled.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(dirname "$0")/../../programs/claude/hooks/lib/session-journal-common.sh"
setup_sandbox; trap teardown_sandbox EXIT

. "$LIB"

# 1. Default: no state file → disabled, and the file is seeded.
sj_enabled && { echo "should be disabled by default"; exit 1; }
assert_file_exists "$HOME/.claude/session-journal-state" "seeded on first check"
assert_eq "$(cat "$HOME/.claude/session-journal-state")" "DISABLED" "seed value"

# 2. State file ENABLED → enabled.
echo ENABLED > "$HOME/.claude/session-journal-state"
sj_enabled || { echo "should be enabled via state file"; exit 1; }

# 3. Env var 0 overrides an ENABLED state file.
SESSION_JOURNAL=0 sj_enabled && { echo "env 0 must override"; exit 1; }

# 4. Env var 1 overrides a DISABLED state file.
echo DISABLED > "$HOME/.claude/session-journal-state"
SESSION_JOURNAL=1 sj_enabled || { echo "env 1 must override"; exit 1; }

# 5. Per-repo opt-out beats an ENABLED state file.
echo ENABLED > "$HOME/.claude/session-journal-state"
touch "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"
( cd "$CMUX_AGENT_LAUNCH_CWD" && sj_enabled ) && { echo ".no-session-journal must disable"; exit 1; }
rm "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"

# 6. Per-repo opt-in beats a DISABLED state file.
echo DISABLED > "$HOME/.claude/session-journal-state"
touch "$CMUX_AGENT_LAUNCH_CWD/.session-journal"
( cd "$CMUX_AGENT_LAUNCH_CWD" && sj_enabled ) || { echo ".session-journal must enable"; exit 1; }

echo "test-enabled passed"
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/session-journal/run-tests.sh`
Expected: FAIL — `session-journal-common.sh` does not exist.

- [ ] **Step 4: Implement just the enable check**

Create `programs/claude/hooks/lib/session-journal-common.sh` with the header and `sj_enabled` only:

```bash
#!/usr/bin/env bash
# Shared library for the session-journal hooks and CLI.
# Sourced, never executed. The ONLY place that touches a journal on disk.

SJ_STATE_FILE="${SJ_STATE_FILE:-$HOME/.claude/session-journal-state}"
SJ_PAGES_DIR="${SJ_PAGES_DIR:-$HOME/html-pages}"
SJ_RUNTIME_DIR="${SJ_RUNTIME_DIR:-$HOME/.claude/session-journal}"
SJ_MAX_BODY=4096

# Resolution order (first match wins):
#   1. SESSION_JOURNAL=0/1 env var
#   2. .session-journal / .no-session-journal in the repo root
#   3. ~/.claude/session-journal-state (ENABLED/DISABLED)
#   4. default DISABLED (opt-in), seeded on first read
sj_enabled() {
  case "${SESSION_JOURNAL:-}" in
    0|off|false|no) return 1 ;;
    1|on|true|yes)  return 0 ;;
  esac

  local root; root=$(sj_repo_root)
  [ -n "$root" ] && [ -e "$root/.no-session-journal" ] && return 1
  [ -n "$root" ] && [ -e "$root/.session-journal" ] && return 0

  if [ ! -f "$SJ_STATE_FILE" ]; then
    mkdir -p "$(dirname "$SJ_STATE_FILE")" 2>/dev/null
    printf 'DISABLED\n' > "$SJ_STATE_FILE" 2>/dev/null
    return 1
  fi
  [ "$(tr -d '[:space:]' < "$SJ_STATE_FILE")" = "ENABLED" ]
}

# Repo root of the workspace, preferring cmux's launch dir over a wandering pwd.
sj_repo_root() {
  local dir="${CMUX_AGENT_LAUNCH_CWD:-$PWD}"
  [ -d "$dir" ] || dir="$PWD"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/session-journal/run-tests.sh`
Expected: `ok test-enabled.sh` and `1 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add tests/session-journal programs/claude/hooks/lib/session-journal-common.sh
git commit -m "feat(session-journal): enable-flag resolution with tests"
```

---

## Task 2: Identity resolution

Derives the journal's stable folder name. Gets its own task because the collision bug it fixes is the subtlest one in the design.

**Files:**
- Modify: `programs/claude/hooks/lib/session-journal-common.sh`
- Create: `tests/session-journal/test-identity.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-identity.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(dirname "$0")/../../programs/claude/hooks/lib/session-journal-common.sh"
setup_sandbox; trap teardown_sandbox EXIT
. "$LIB"

git -C "$CMUX_AGENT_LAUNCH_CWD" init -q -b main 2>/dev/null

# wsid8 = first 8 chars of the workspace uuid, lowercased.
assert_eq "$(sj_wsid8)" "11111111" "wsid8 from CMUX_WORKSPACE_ID"

# Slug is <date>-session-<repo>-<branch>-<wsid8>.
slug=$(sj_slug)
assert_contains "$slug" "session-" "slug marker"
assert_contains "$slug" "11111111" "slug carries workspace id"
assert_contains "$slug" "main" "slug carries branch"
case "$slug" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-session-*) ;;
  *) echo "slug must start with a date: $slug"; exit 1;; esac

# Slug is STABLE across calls (no re-dating).
assert_eq "$(sj_slug)" "$slug" "slug stable"

# Two different workspaces on the same repo+branch MUST differ. This is the
# collision the wsid8 suffix exists to prevent.
a=$(sj_slug)
b=$(CMUX_WORKSPACE_ID="99999999-0000-0000-0000-000000000000" sj_slug)
[ "$a" != "$b" ] || { echo "distinct workspaces collided: $a"; exit 1; }

# Branch names with slashes must not create nested directories.
git -C "$CMUX_AGENT_LAUNCH_CWD" checkout -q -b feature/foo/bar 2>/dev/null
s=$(sj_slug)
case "$s" in */*) echo "slug must not contain a slash: $s"; exit 1;; esac

# No cmux env → still stable and unique via a cwd-derived hash.
s1=$(env -u CMUX_WORKSPACE_ID bash -c ". '$LIB'; sj_slug")
s2=$(env -u CMUX_WORKSPACE_ID bash -c ". '$LIB'; sj_slug")
assert_eq "$s1" "$s2" "fallback identity stable"

echo "test-identity passed"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/session-journal/run-tests.sh`
Expected: FAIL — `sj_wsid8: command not found`.

- [ ] **Step 3: Implement identity resolution**

Append to `session-journal-common.sh`:

```bash
# Short, stable workspace discriminator. Without this two workspaces on the same
# repo AND branch, created the same day, would share a folder and silently merge.
sj_wsid8() {
  local id="${CMUX_WORKSPACE_ID:-}"
  if [ -z "$id" ]; then
    # Outside cmux: derive a stable hash from the launch dir instead.
    id=$(printf '%s' "$(sj_repo_root)" | shasum -a 256 | cut -c1-8)
  fi
  printf '%s' "$id" | tr 'A-Z' 'a-z' | tr -cd 'a-f0-9' | cut -c1-8
}

sj_sanitize() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//'; }

sj_repo_name()  { basename "$(sj_repo_root)"; }
sj_branch_name() { git -C "$(sj_repo_root)" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'nogit'; }

# <YYYY-MM-DD>-session-<repo>-<branch>-<wsid8>. The date is CREATION date: once
# the directory exists we reuse it forever (requirement: no rotation).
sj_slug() {
  local wsid8; wsid8=$(sj_wsid8)
  local existing
  existing=$(find "$SJ_PAGES_DIR" -maxdepth 1 -type d -name "*-session-*-$wsid8" 2>/dev/null | head -1)
  if [ -n "$existing" ]; then basename "$existing"; return; fi
  printf '%s-session-%s-%s-%s' "$(date +%F)" \
    "$(sj_sanitize "$(sj_repo_name)")" "$(sj_sanitize "$(sj_branch_name)")" "$wsid8"
}

sj_dir() { printf '%s/%s' "$SJ_PAGES_DIR" "$(sj_slug)"; }
```

- [ ] **Step 4: Run tests**

Run: `bash tests/session-journal/run-tests.sh`
Expected: `2 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add -A tests/session-journal programs/claude/hooks/lib
git commit -m "feat(session-journal): stable per-workspace identity with collision-proof slug"
```

---

## Task 3: Concurrency-safe append

**Files:**
- Modify: `programs/claude/hooks/lib/session-journal-common.sh`
- Create: `tests/session-journal/test-append.sh`
- Create: `tests/session-journal/test-concurrency.sh`

- [ ] **Step 1: Write the append test**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-append.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(dirname "$0")/../../programs/claude/hooks/lib/session-journal-common.sh"
setup_sandbox; trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED > "$HOME/.claude/session-journal-state"

d=$(sj_dir); mkdir -p "$d"
sj_append "decision" "agent" "Picked bash" "Because hooks must start fast"

f="$d/entries.txt"
assert_file_exists "$f"
assert_eq "$(wc -l < "$f" | tr -d ' ')" "1" "one line"
echo "$(cat "$f")" | jq -e . >/dev/null || { echo "not valid json"; exit 1; }
assert_eq "$(jq -r .kind < "$f")" "decision"
assert_eq "$(jq -r .source < "$f")" "agent"
assert_eq "$(jq -r .title < "$f")" "Picked bash"
assert_eq "$(jq -r .body < "$f")" "Because hooks must start fast"
assert_eq "$(jq -r .workspace_id < "$f")" "$CMUX_WORKSPACE_ID"

# Embedded newlines/quotes must not break the one-line-per-entry invariant.
sj_append "progress" "agent" 'Title with "quotes"' 'line1
line2	tabbed'
assert_eq "$(wc -l < "$f" | tr -d ' ')" "2" "still one line per entry"
while read -r l; do echo "$l" | jq -e . >/dev/null || { echo "corrupt line"; exit 1; }; done < "$f"
assert_contains "$(jq -r 'select(.kind=="progress").body' < "$f")" "line2" "newline preserved in json"

# Oversized bodies are truncated, not dropped.
sj_append "progress" "agent" "big" "$(head -c 20000 </dev/zero | tr '\0' 'x')"
last=$(tail -1 "$f")
echo "$last" | jq -e . >/dev/null || { echo "oversized corrupted json"; exit 1; }
blen=$(echo "$last" | jq -r .body | wc -c | tr -d ' ')
[ "$blen" -le 4200 ] || { echo "body not truncated: $blen"; exit 1; }
assert_contains "$(echo "$last" | jq -r .body)" "truncated" "truncation marker"

echo "test-append passed"
```

- [ ] **Step 2: Write the concurrency test**

This is the test that justifies the mutex. `flock` is unavailable on macOS, so we verify the `mkdir`-based one.

```bash
#!/usr/bin/env bash
# tests/session-journal/test-concurrency.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(realpath "$(dirname "$0")/../../programs/claude/hooks/lib/session-journal-common.sh")"
setup_sandbox; trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED > "$HOME/.claude/session-journal-state"
d=$(sj_dir); mkdir -p "$d"

WRITERS=8; PER=40; EXPECTED=$((WRITERS*PER))
for w in $(seq 1 $WRITERS); do
  ( . "$LIB"
    for i in $(seq 1 $PER); do
      sj_append "progress" "agent" "w$w-$i" "$(head -c 500 </dev/zero | tr '\0' 'y')"
    done ) &
done
wait

f="$d/entries.txt"
got=$(wc -l < "$f" | tr -d ' ')
assert_eq "$got" "$EXPECTED" "no lost or duplicated writes"
bad=0
while read -r l; do echo "$l" | jq -e . >/dev/null 2>&1 || bad=$((bad+1)); done < "$f"
assert_eq "$bad" "0" "no torn lines"
uniq=$(jq -r .title < "$f" | sort -u | wc -l | tr -d ' ')
assert_eq "$uniq" "$EXPECTED" "every entry distinct"

echo "test-concurrency passed"
```

- [ ] **Step 3: Run to verify both fail**

Run: `bash tests/session-journal/run-tests.sh`
Expected: FAIL — `sj_append: command not found`.

- [ ] **Step 4: Implement the mutex and append**

Append to `session-journal-common.sh`:

```bash
# --- Mutex -------------------------------------------------------------------
# macOS has no flock(1). mkdir(2) is atomic on APFS, so a lock DIRECTORY is the
# portable primitive. Verified: 8 writers x 60 entries -> 480 intact JSON lines.
sj_lock() {
  local dir="$1/.lock" n=0
  until mkdir "$dir" 2>/dev/null; do
    n=$((n+1))
    if [ "$n" -gt 3000 ]; then          # ~3s: assume a crashed holder
      rmdir "$dir" 2>/dev/null || true
      mkdir "$dir" 2>/dev/null && break
      return 1
    fi
    sleep 0.001
  done
  return 0
}
sj_unlock() { rmdir "$1/.lock" 2>/dev/null || true; }

# --- Append ------------------------------------------------------------------
# One JSON object per line. jq -c does the escaping, so newlines/quotes/tabs in
# the body can never break the one-entry-per-line invariant.
# Args: kind source title body
sj_append() {
  local kind="$1" source="$2" title="$3" body="${4:-}"
  local dir; dir=$(sj_dir)
  [ -d "$dir" ] || return 1

  if [ "${#body}" -gt "$SJ_MAX_BODY" ]; then
    body="${body:0:$SJ_MAX_BODY}…[truncated]"
  fi

  local line
  line=$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg kind "$kind" --arg source "$source" \
    --arg title "$title" --arg body "$body" \
    --arg session_id "${SJ_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}" \
    --arg pane_id "${CMUX_PANEL_ID:-}" \
    --arg workspace_id "${CMUX_WORKSPACE_ID:-}" \
    --arg agent "${SJ_AGENT:-main}" \
    '{ts:$ts,kind:$kind,source:$source,title:$title,body:$body,
      session_id:$session_id,pane_id:$pane_id,workspace_id:$workspace_id,agent:$agent}') || return 1

  sj_lock "$dir" || return 1
  printf '%s\n' "$line" >> "$dir/entries.txt"
  sj_unlock "$dir"
}
```

- [ ] **Step 5: Run tests**

Run: `bash tests/session-journal/run-tests.sh`
Expected: `4 passed, 0 failed`. The concurrency test takes a few seconds.

- [ ] **Step 6: Commit**

```bash
git add -A tests programs/claude/hooks/lib
git commit -m "feat(session-journal): mkdir-mutex append, safe under concurrent writers"
```

---

## Task 4: `meta.json` maintenance

Read-modify-write from many writers — per the spec this is the hazard that actually matters, because a torn `meta.json` fails silently.

**Files:**
- Modify: `programs/claude/hooks/lib/session-journal-common.sh`
- Create: `tests/session-journal/test-meta.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-meta.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(realpath "$(dirname "$0")/../../programs/claude/hooks/lib/session-journal-common.sh")"
setup_sandbox; trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED > "$HOME/.claude/session-journal-state"
d=$(sj_dir); mkdir -p "$d"

sj_meta_init
m="$d/meta.json"
assert_file_exists "$m"
jq -e . "$m" >/dev/null || { echo "invalid meta.json"; exit 1; }
assert_eq "$(jq -r .kind "$m")" "session-journal"
assert_eq "$(jq -r .style "$m")" "Session journal"
assert_eq "$(jq -r .cmux_workspace_id "$m")" "$CMUX_WORKSPACE_ID"

# Session ids accumulate, never duplicate (autoResumeAgentSessions restarts).
SJ_SESSION_ID="aaa" sj_meta_touch
SJ_SESSION_ID="bbb" sj_meta_touch
SJ_SESSION_ID="aaa" sj_meta_touch
assert_eq "$(jq -r '.session_ids|length' "$m")" "2" "ids deduped"

# `date` tracks LAST-UPDATED so active journals float to the top of the gallery.
assert_eq "$(jq -r .date "$m")" "$(date +%F)" "date is last-updated"

# No temp files left behind.
assert_eq "$(find "$d" -name 'meta.json.tmp*' | wc -l | tr -d ' ')" "0" "no tmp litter"

# Concurrent meta updates must never produce a torn file.
for i in $(seq 1 8); do
  ( . "$LIB"; for j in $(seq 1 15); do SJ_SESSION_ID="s$i-$j" sj_meta_touch; done ) &
done
wait
jq -e . "$m" >/dev/null || { echo "meta.json torn by concurrent writers"; exit 1; }
assert_eq "$(jq -r '.session_ids|length' "$m")" "122" "all ids recorded (2 + 120)"

echo "test-meta passed"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/session-journal/run-tests.sh`
Expected: FAIL — `sj_meta_init: command not found`.

- [ ] **Step 3: Implement meta handling**

Append to `session-journal-common.sh`:

```bash
# --- meta.json ---------------------------------------------------------------
# The gallery reads this sidecar for title/style/date (server.js:99-114) and
# ignores our marker fields, so markers are for filesystem discovery.
# ALWAYS write via tmp+mv: rename(2) is atomic, so a reader never sees a partial
# file. A torn meta.json degrades SILENTLY to title-only, so this matters.
sj_meta_write() {                      # stdin: complete JSON. Caller holds the lock.
  local dir="$1" tmp="$1/meta.json.tmp.$$"
  cat > "$tmp" || return 1
  if jq -e . "$tmp" >/dev/null 2>&1; then mv -f "$tmp" "$1/meta.json"; else rm -f "$tmp"; return 1; fi
}

sj_meta_init() {
  local dir; dir=$(sj_dir)
  [ -f "$dir/meta.json" ] && return 0
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sj_lock "$dir" || return 1
  if [ ! -f "$dir/meta.json" ]; then
    jq -n \
      --arg title "$(sj_repo_name) · $(sj_branch_name)" \
      --arg date "$(date +%F)" \
      --arg ws "${CMUX_WORKSPACE_ID:-}" --arg cwd "$(sj_repo_root)" \
      --arg launch "${CMUX_AGENT_LAUNCH_CWD:-}" \
      --arg repo "$(sj_repo_name)" --arg branch "$(sj_branch_name)" \
      --arg common "$(git -C "$(sj_repo_root)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo '')" \
      --arg started "$now" --arg updated "$now" \
      '{kind:"session-journal", title:$title, style:"Session journal",
        keywords:"live session log · decisions · progress",
        recreate:"Session journal — auto-maintained by the session-journal hooks.",
        date:$date, cmux_workspace_id:$ws, session_ids:[], pane_ids:[],
        cwd:$cwd, launch_cwd:$launch, repo:$repo, branch:$branch,
        git_common_dir:$common, started:$started, updated:$updated}' \
      | sj_meta_write "$dir"
  fi
  sj_unlock "$dir"
}

# Refresh updated/date and accumulate session+pane ids. Writes only when the
# content actually changes: meta.json IS inside the server's fs.watch filter, so
# a needless write reloads every open gallery tab.
sj_meta_touch() {
  local dir; dir=$(sj_dir)
  [ -f "$dir/meta.json" ] || return 0
  local sid="${SJ_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}" pid="${CMUX_PANEL_ID:-}"
  local today; today=$(date +%F)

  # Cheap pre-check outside the lock: skip if nothing would change.
  local cur_date cur_has_s cur_has_p
  cur_date=$(jq -r .date "$dir/meta.json" 2>/dev/null)
  cur_has_s=$(jq -r --arg s "$sid" '(.session_ids//[])|index($s)!=null' "$dir/meta.json" 2>/dev/null)
  cur_has_p=$(jq -r --arg p "$pid" '(.pane_ids//[])|index($p)!=null' "$dir/meta.json" 2>/dev/null)
  if [ "$cur_date" = "$today" ] && [ "$cur_has_s" = "true" ] && [ "$cur_has_p" = "true" ]; then
    return 0
  fi

  sj_lock "$dir" || return 1
  jq --arg s "$sid" --arg p "$pid" --arg d "$today" \
     --arg u "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.date=$d | .updated=$u
      | .session_ids = ((.session_ids//[]) + (if $s=="" then [] else [$s] end) | unique)
      | .pane_ids    = ((.pane_ids//[])    + (if $p=="" then [] else [$p] end) | unique)' \
     "$dir/meta.json" | sj_meta_write "$dir"
  sj_unlock "$dir"
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/session-journal/run-tests.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add -A tests programs/claude/hooks/lib
git commit -m "feat(session-journal): atomic meta.json via tmp+rename, write-only-on-change"
```

---

## Task 5: The page template

**Files:**
- Create: `programs/claude/hooks/lib/journal-template.html`

- [ ] **Step 1: Write the template**

Requirements this encodes:
- Never opens an `EventSource` (immune to the gallery's reload broadcasts).
- Polls `entries.txt` every 3s; renders newest-first.
- Carries discovery markers in `<meta>` tags and a JSON `<script>` block.
- Carries the html-page `<dl>` stamp so the gallery extracts metadata.
- Readable contrast, works at 375px, respects `prefers-reduced-motion`.

Placeholders `{{TITLE}} {{REPO}} {{BRANCH}} {{WORKSPACE_ID}} {{CWD}} {{CREATED}}` are substituted at init.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}} — session journal</title>

<!-- Discovery markers: let an agent identify this journal over HTTP. -->
<meta name="session-journal:workspace-id" content="{{WORKSPACE_ID}}">
<meta name="session-journal:repo" content="{{REPO}}">
<meta name="session-journal:branch" content="{{BRANCH}}">
<meta name="session-journal:cwd" content="{{CWD}}">
<script type="application/json" id="sj-markers">
{"kind":"session-journal","workspace_id":"{{WORKSPACE_ID}}","repo":"{{REPO}}",
 "branch":"{{BRANCH}}","cwd":"{{CWD}}","created":"{{CREATED}}",
 "note":"session_ids and pane_ids accumulate in meta.json and entries.txt"}
</script>

<style>
  :root{
    --bg:#12131a; --panel:#181a23; --line:#272a37; --ink:#e7e9f0; --dim:#9aa0b4;
    --accent:#7aa2f7; --agent:#9ece6a; --hook:#7a7f95; --sub:#bb9af7; --warn:#f7768e;
    --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,monospace;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);
       font:14px/1.55 var(--mono);padding:24px 20px 80px;}
  header{max-width:900px;margin:0 auto 20px;border-bottom:1px solid var(--line);padding-bottom:14px}
  h1{margin:0 0 6px;font-size:17px;letter-spacing:.3px}
  .sub{color:var(--dim);font-size:12px;display:flex;flex-wrap:wrap;gap:12px}
  .bar{max-width:900px;margin:0 auto 14px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
  .bar button{background:var(--panel);color:var(--dim);border:1px solid var(--line);
    border-radius:5px;padding:4px 10px;font:12px var(--mono);cursor:pointer}
  .bar button[aria-pressed="true"]{color:var(--ink);border-color:var(--accent)}
  #live{margin-left:auto;color:var(--dim);font-size:11px}
  #log{max-width:900px;margin:0 auto;display:flex;flex-direction:column;gap:8px}
  .e{background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--hook);
     border-radius:6px;padding:9px 12px}
  .e[data-source="agent"]{border-left-color:var(--agent)}
  .e[data-source="subagent"]{border-left-color:var(--sub)}
  .e[data-kind="blocker"]{border-left-color:var(--warn)}
  .m{display:flex;gap:9px;align-items:baseline;font-size:11px;color:var(--dim);flex-wrap:wrap}
  .k{color:var(--accent);text-transform:uppercase;letter-spacing:.6px}
  .t{margin:3px 0 0;font-size:13.5px;color:var(--ink)}
  .b{margin:6px 0 0;white-space:pre-wrap;color:#c3c8d8;font-size:12.5px;
     border-top:1px dashed var(--line);padding-top:6px}
  .empty{color:var(--dim);text-align:center;padding:48px 0}
  footer{max-width:900px;margin:34px auto 0;color:var(--dim);font-size:11px}
  footer dl{display:grid;grid-template-columns:auto 1fr;gap:2px 10px;margin:8px 0 0}
  footer dt{color:var(--accent)} footer dd{margin:0}
  @media (max-width:420px){ body{padding:14px 10px 60px} .sub{gap:6px} }
  @media (prefers-reduced-motion:reduce){ *{transition:none!important;animation:none!important} }
</style>
</head>
<body>
<header>
  <h1>{{TITLE}}</h1>
  <div class="sub">
    <span>{{REPO}} · {{BRANCH}}</span>
    <span>workspace {{WORKSPACE_ID}}</span>
    <span id="count">—</span>
  </div>
</header>

<div class="bar" role="group" aria-label="Filter entries">
  <button data-f="all" aria-pressed="true">all</button>
  <button data-f="agent" aria-pressed="false">reasoning</button>
  <button data-f="hook" aria-pressed="false">activity</button>
  <button data-f="subagent" aria-pressed="false">subagents</button>
  <span id="live">connecting…</span>
</div>

<main id="log"><div class="empty">No entries yet.</div></main>

<footer>
  <!-- html-page stamp: the gallery extracts these <dt> labels. -->
  <dl>
    <dt>Style</dt><dd>Session journal</dd>
    <dt>Keywords</dt><dd>live session log · decisions · progress</dd>
    <dt>Recreate prompt</dt><dd>Session journal — auto-maintained by the session-journal hooks.</dd>
  </dl>
  <p>Auto-updating · created {{CREATED}}</p>
</footer>

<script>
// NOTE: deliberately no EventSource. The gallery server broadcasts SSE reloads
// on file changes; subscribing would make this page reload on every append.
const log = document.getElementById('log');
const countEl = document.getElementById('count');
const liveEl = document.getElementById('live');
let filter = 'all', lastRaw = null;

const esc = s => String(s ?? '').replace(/[&<>"']/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function timeAgo(iso){
  const s = Math.floor((Date.now() - new Date(iso)) / 1000);
  if (isNaN(s)) return '';
  if (s < 60) return s + 's ago';
  if (s < 3600) return Math.floor(s/60) + 'm ago';
  if (s < 86400) return Math.floor(s/3600) + 'h ago';
  return Math.floor(s/86400) + 'd ago';
}

function render(entries){
  const list = entries.filter(e => filter === 'all' || e.source === filter).reverse();
  countEl.textContent = entries.length + ' entries';
  if (!list.length){ log.innerHTML = '<div class="empty">No entries match.</div>'; return; }
  log.innerHTML = list.map(e => `
    <article class="e" data-source="${esc(e.source)}" data-kind="${esc(e.kind)}">
      <div class="m">
        <span class="k">${esc(e.kind)}</span>
        <span title="${esc(e.ts)}">${esc(timeAgo(e.ts))}</span>
        ${e.agent && e.agent !== 'main' ? `<span>${esc(e.agent)}</span>` : ''}
        ${e.pane_id ? `<span>pane ${esc(e.pane_id.slice(0,6))}</span>` : ''}
      </div>
      <p class="t">${esc(e.title)}</p>
      ${e.body ? `<div class="b">${esc(e.body)}</div>` : ''}
    </article>`).join('');
}

async function poll(){
  try {
    const r = await fetch('entries.txt?t=' + Date.now(), {cache:'no-store'});
    if (!r.ok) throw new Error(r.status);
    const raw = await r.text();
    liveEl.textContent = 'live';
    if (raw === lastRaw) return;
    lastRaw = raw;
    const entries = raw.split('\n').filter(Boolean).map(l => {
      try { return JSON.parse(l); } catch { return null; }
    }).filter(Boolean);
    render(entries);
  } catch (err) {
    liveEl.textContent = 'offline — open via http://localhost:7777';
  }
}

document.querySelectorAll('.bar button').forEach(b => b.addEventListener('click', () => {
  filter = b.dataset.f;
  document.querySelectorAll('.bar button').forEach(x =>
    x.setAttribute('aria-pressed', String(x === b)));
  if (lastRaw !== null){
    render(lastRaw.split('\n').filter(Boolean)
      .map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean));
  }
}));

poll();
setInterval(poll, 3000);
</script>
</body>
</html>
```

- [ ] **Step 2: Sanity-check it renders**

```bash
mkdir -p /tmp/sjpreview
sed -e 's/{{TITLE}}/demo/g' -e 's/{{REPO}}/demo/g' -e 's/{{BRANCH}}/main/g' \
    -e 's/{{WORKSPACE_ID}}/abcd1234/g' -e 's#{{CWD}}#/tmp#g' -e 's/{{CREATED}}/2026-08-06/g' \
    programs/claude/hooks/lib/journal-template.html > /tmp/sjpreview/index.html
printf '%s\n' '{"ts":"2026-08-06T10:00:00Z","kind":"decision","source":"agent","title":"Chose mkdir mutex","body":"flock is unavailable on macOS.","agent":"main","pane_id":"p1"}' > /tmp/sjpreview/entries.txt
open /tmp/sjpreview/index.html
```

Expected: dark page, one green-bordered entry, filter buttons work. The live indicator will read "offline" over `file://` — correct, since `fetch` is blocked there.

- [ ] **Step 3: Commit**

```bash
git add programs/claude/hooks/lib/journal-template.html
git commit -m "feat(session-journal): page template with markers, polling, no SSE"
```

---

## Task 6: The `session-journal` CLI

**Files:**
- Create: `programs/claude/hooks/session-journal`
- Modify: `programs/claude/hooks/lib/session-journal-common.sh` (add `sj_init`)
- Create: `tests/session-journal/test-cli.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-cli.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(realpath "$(dirname "$0")/../..")"
CLI="$ROOT/programs/claude/hooks/session-journal"
setup_sandbox; trap teardown_sandbox EXIT

# Disabled by default: add must no-op, silently, with exit 0 (never break a hook).
"$CLI" add --kind decision --title "should not appear" || { echo "must exit 0 when disabled"; exit 1; }
assert_eq "$(find "$SJ_PAGES_DIR" -name entries.txt | wc -l | tr -d ' ')" "0" "nothing written when disabled"

echo ENABLED > "$HOME/.claude/session-journal-state"

"$CLI" init || { echo "init failed"; exit 1; }
d=$("$CLI" path)
assert_file_exists "$d/index.html" "index.html written FIRST or gallery skips the dir"
assert_file_exists "$d/entries.txt"
assert_file_exists "$d/meta.json"

# Template placeholders must all be substituted.
grep -q '{{' "$d/index.html" && { echo "unsubstituted placeholder left in page"; exit 1; }
grep -q 'session-journal:workspace-id' "$d/index.html" || { echo "missing marker meta tag"; exit 1; }
grep -q "$CMUX_WORKSPACE_ID" "$d/index.html" || { echo "workspace id not embedded"; exit 1; }

# init is idempotent and must not clobber existing entries.
"$CLI" add --kind progress --title "first"
"$CLI" init
assert_eq "$(wc -l < "$d/entries.txt" | tr -d ' ')" "1" "init preserved entries"

"$CLI" add --kind decision --title "chose X" --body "because Y"
assert_eq "$(wc -l < "$d/entries.txt" | tr -d ' ')" "2"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .title)" "chose X"

# Body from stdin, for long text.
echo "streamed body" | "$CLI" add --kind progress --title "from stdin" --body-stdin
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .body)" "streamed body"

# tail is bounded — the file is never pruned, so unbounded reads are a bug.
"$CLI" tail -n 2 | wc -l | grep -q 2 || { echo "tail -n 2 must return 2"; exit 1; }

"$CLI" status | grep -q ENABLED || { echo "status should report ENABLED"; exit 1; }

# A bad --kind is rejected rather than silently written.
"$CLI" add --kind bogus --title x 2>/dev/null && { echo "invalid kind must fail"; exit 1; }

echo "test-cli passed"
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — CLI does not exist.

- [ ] **Step 3: Add `sj_init` to the library**

```bash
# --- init --------------------------------------------------------------------
# ORDER MATTERS: index.html first. listPages() skips any directory whose
# index.html cannot be stat'd (server.js:145-147), so a journal created in the
# other order is invisible in the gallery with no error anywhere.
sj_init() {
  local dir; dir=$(sj_dir)
  mkdir -p "$dir" || return 1
  local tpl="${SJ_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/journal-template.html}"

  if [ ! -f "$dir/index.html" ]; then
    [ -f "$tpl" ] || { echo "session-journal: template missing: $tpl" >&2; return 1; }
    local tmp="$dir/index.html.tmp.$$"
    sed -e "s|{{TITLE}}|$(sj_esc_html "$(sj_repo_name) · $(sj_branch_name)")|g" \
        -e "s|{{REPO}}|$(sj_esc_html "$(sj_repo_name)")|g" \
        -e "s|{{BRANCH}}|$(sj_esc_html "$(sj_branch_name)")|g" \
        -e "s|{{WORKSPACE_ID}}|$(sj_esc_html "${CMUX_WORKSPACE_ID:-$(sj_wsid8)}")|g" \
        -e "s|{{CWD}}|$(sj_esc_html "$(sj_repo_root)")|g" \
        -e "s|{{CREATED}}|$(date +%F)|g" \
        "$tpl" > "$tmp" && mv -f "$tmp" "$dir/index.html" || { rm -f "$tmp"; return 1; }
  fi

  [ -f "$dir/entries.txt" ] || : > "$dir/entries.txt"
  sj_meta_init
}

# Minimal escaping for values interpolated into the page. Branch names can
# contain & and < in principle; sed delimiters are handled by using | above.
sj_esc_html() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/|/-/g'; }
```

- [ ] **Step 4: Write the CLI**

```bash
#!/usr/bin/env bash
# session-journal — per-cmux-workspace session journal.
#
#   session-journal init
#   session-journal add --kind <kind> --title <t> [--body <b> | --body-stdin]
#   session-journal tail [-n N]
#   session-journal path | status
#
# Exits 0 when journaling is disabled so a hook never fails because of us.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/session-journal-common.sh"

SJ_KINDS="decision progress blocker milestone question files commit subagent session"

die() { echo "session-journal: $*" >&2; exit 1; }

cmd_init() { sj_enabled || exit 0; sj_init || die "init failed"; }

cmd_add() {
  local kind="" title="" body="" source="${SJ_SOURCE:-agent}" from_stdin=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind)       kind="${2:-}"; shift 2 ;;
      --title)      title="${2:-}"; shift 2 ;;
      --body)       body="${2:-}"; shift 2 ;;
      --body-stdin) from_stdin=1; shift ;;
      --source)     source="${2:-}"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -n "$kind" ]  || die "--kind is required"
  [ -n "$title" ] || die "--title is required"
  case " $SJ_KINDS " in *" $kind "*) ;; *) die "invalid --kind: $kind (one of: $SJ_KINDS)";; esac

  # Validate BEFORE the enabled check so typos surface even while disabled.
  sj_enabled || exit 0
  [ "$from_stdin" -eq 1 ] && body=$(cat)

  sj_init || exit 0          # auto-create; never fail a hook
  sj_append "$kind" "$source" "$title" "$body" || exit 0
  sj_meta_touch || true
}

cmd_tail() {
  sj_enabled || exit 0
  local n=20
  [ "${1:-}" = "-n" ] && { n="${2:-20}"; }
  local f; f="$(sj_dir)/entries.txt"
  [ -f "$f" ] || exit 0
  tail -n "$n" "$f"
}

cmd_path()   { sj_dir; }
cmd_status() {
  if sj_enabled; then echo "ENABLED  $(sj_dir)"; else echo "DISABLED ($(sj_dir))"; fi
}

case "${1:-}" in
  init)   shift; cmd_init "$@" ;;
  add)    shift; cmd_add "$@" ;;
  tail)   shift; cmd_tail "$@" ;;
  path)   shift; cmd_path "$@" ;;
  status) shift; cmd_status "$@" ;;
  *) echo "usage: session-journal {init|add|tail|path|status}" >&2; exit 2 ;;
esac
```

- [ ] **Step 5: Make executable and run tests**

```bash
chmod +x programs/claude/hooks/session-journal
bash tests/session-journal/run-tests.sh
```

Expected: `6 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add -A tests programs/claude/hooks
git commit -m "feat(session-journal): CLI with init/add/tail/path/status"
```

---

## Task 7: Hook scripts

**Files:**
- Create: `programs/claude/hooks/session-journal-{start,tool,subagent,stop}.sh`
- Create: `tests/session-journal/test-hooks.sh`

Hook stdin payloads carry at least `session_id`, `cwd`, `transcript_path`, plus
`hook_event_name`. `PostToolUse` adds `tool_name`, `tool_input`, `tool_response`.
**The exact `SubagentStop` shape is unverified** (spec open item) — the script
must therefore degrade gracefully when fields are absent, and Task 9 captures the
real payload.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/session-journal/test-hooks.sh
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(realpath "$(dirname "$0")/../..")"
H="$ROOT/programs/claude/hooks"
setup_sandbox; trap teardown_sandbox EXIT
echo ENABLED > "$HOME/.claude/session-journal-state"

# SessionStart: creates the journal and emits additionalContext for the model.
out=$(echo '{"session_id":"s1","cwd":"'"$CMUX_AGENT_LAUNCH_CWD"'","source":"startup"}' \
  | bash "$H/session-journal-start.sh")
d=$("$H/session-journal" path)
assert_file_exists "$d/index.html"
echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null \
  || { echo "SessionStart must inject context"; exit 1; }
assert_contains "$out" "session-journal" "context mentions the tool"

# PostToolUse buffers file edits rather than writing one entry per edit.
for f in a.ts b.ts c.ts; do
  echo '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/repo/'"$f"'"}}' \
    | bash "$H/session-journal-tool.sh"
done
assert_eq "$(grep -c . "$d/entries.txt" 2>/dev/null || echo 0)" "1" "only the session entry so far"

# Stop flushes the buffer as ONE coalesced entry.
echo '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_eq "$(echo "$last" | jq -r .kind)" "files"
assert_contains "$(echo "$last" | jq -r .body)" "a.ts" "coalesced body lists files"
assert_contains "$(echo "$last" | jq -r .title)" "3" "count in title"

# Buffer cleared: a second Stop with no activity adds nothing.
before=$(wc -l < "$d/entries.txt")
echo '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" >/dev/null
assert_eq "$(wc -l < "$d/entries.txt")" "$before" "no empty flush"

# git commit is captured; ordinary bash commands are not.
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: thing\""}}' \
  | bash "$H/session-journal-tool.sh"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .kind)" "commit"
echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | bash "$H/session-journal-tool.sh"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .kind)" "commit" "ls must not be logged"

# SubagentStop records a subagent entry tagged as such.
echo '{"session_id":"s1","agent_type":"Explore"}' | bash "$H/session-journal-subagent.sh" >/dev/null
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .source)" "subagent"

# Disabled → hooks are silent no-ops that still exit 0.
echo DISABLED > "$HOME/.claude/session-journal-state"
before=$(wc -l < "$d/entries.txt")
echo '{"session_id":"s2"}' | bash "$H/session-journal-start.sh" >/dev/null || { echo "must exit 0"; exit 1; }
assert_eq "$(wc -l < "$d/entries.txt")" "$before" "no writes when disabled"

# Malformed stdin must never crash a hook.
echo 'not json' | bash "$H/session-journal-stop.sh" >/dev/null || { echo "must survive bad json"; exit 1; }

echo "test-hooks passed"
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `session-journal-start.sh`**

```bash
#!/usr/bin/env bash
# SessionStart: open/attach the workspace journal and remind the model to use it.
set -uo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DIR/lib/session-journal-common.sh"
sj_enabled || exit 0

payload=$(cat 2>/dev/null || echo '{}')
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID
src=$(printf '%s' "$payload" | jq -r '.source // "startup"' 2>/dev/null)

sj_init || exit 0
SJ_SOURCE=hook sj_append "session" "hook" \
  "Session $src — $(sj_repo_name) · $(sj_branch_name)" "session_id: $SJ_SESSION_ID" || true
sj_meta_touch || true

jq -n --arg d "$(sj_dir)" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: (
      "SESSION JOURNAL ACTIVE. This workspace keeps a shared journal at \($d).\n" +
      "Record the reasoning that would otherwise be lost when the chat scrolls:\n" +
      "  session-journal add --kind <decision|progress|blocker|milestone|question> \\\n" +
      "      --title \"<one line>\" --body \"<why, alternatives, tradeoffs>\"\n" +
      "Log a `decision` whenever you choose between real alternatives, a `blocker` when stuck,\n" +
      "and a `milestone` when something meaningful starts working. Do NOT log routine file edits\n" +
      "(hooks capture those automatically). Write for a human reviewing this later who will ask\n" +
      "you why you did what you did."
    )
  }
}'
```

- [ ] **Step 4: Implement `session-journal-tool.sh`**

```bash
#!/usr/bin/env bash
# PostToolUse: buffer file edits for coalescing; log git commits immediately.
set -uo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DIR/lib/session-journal-common.sh"
sj_enabled || exit 0

payload=$(cat 2>/dev/null || echo '{}')
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
export SJ_SESSION_ID

case "$tool" in
  Edit|Write|NotebookEdit|MultiEdit)
    fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -n "$fp" ] || exit 0
    buf="$SJ_RUNTIME_DIR/$(sj_wsid8)"
    mkdir -p "$buf" 2>/dev/null || exit 0
    printf '%s\n' "$fp" >> "$buf/files.txt" 2>/dev/null || true
    ;;
  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    case "$cmd" in
      *"git commit"*)
        sj_init || exit 0
        msg=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        [ -z "$msg" ] && msg="(commit)"
        sj_append "commit" "hook" "Commit: $msg" "" || true
        ;;
    esac
    ;;
esac
exit 0
```

- [ ] **Step 5: Implement `session-journal-subagent.sh`**

```bash
#!/usr/bin/env bash
# SubagentStop: harvest the subagent's own final report.
#
# This is how subagents contribute WITHOUT being instructed — they skip skills by
# design, and CLAUDE_CODE_CHILD_SESSION is set on every cmux session so it cannot
# discriminate. The hook firing IS the discriminator.
set -uo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DIR/lib/session-journal-common.sh"
sj_enabled || exit 0

payload=$(cat 2>/dev/null || echo '{}')
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
export SJ_SESSION_ID
atype=$(printf '%s' "$payload" | jq -r '
  .agent_type // .subagent_type // .agentType // "subagent"' 2>/dev/null)
[ -z "$atype" ] && atype="subagent"

# Field name unverified across versions — try several, then the transcript.
summary=$(printf '%s' "$payload" | jq -r '
  .result // .final_message // .output // .response // empty' 2>/dev/null)

if [ -z "$summary" ]; then
  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    summary=$(tail -50 "$tp" 2>/dev/null | jq -rs '
      [ .[] | select(.type=="assistant")
             | .message.content[]? | select(.type=="text") | .text ]
      | last // empty' 2>/dev/null)
  fi
fi
[ -z "$summary" ] && summary="(no report captured)"

sj_init || exit 0
title=$(printf '%s' "$summary" | head -1 | cut -c1-120)
[ -z "$title" ] && title="Subagent finished"
SJ_AGENT="$atype" sj_append "subagent" "subagent" "[$atype] $title" "$summary" || true
sj_meta_touch || true
exit 0
```

- [ ] **Step 6: Implement `session-journal-stop.sh`**

```bash
#!/usr/bin/env bash
# Stop: flush the coalesced file-edit buffer, then nudge if reasoning is missing.
set -uo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DIR/lib/session-journal-common.sh"
sj_enabled || exit 0

payload=$(cat 2>/dev/null || echo '{}')
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
export SJ_SESSION_ID

buf="$SJ_RUNTIME_DIR/$(sj_wsid8)"
touched=0
if [ -s "$buf/files.txt" ]; then
  files=$(sort -u "$buf/files.txt" 2>/dev/null)
  n=$(printf '%s\n' "$files" | grep -c . || echo 0)
  if [ "$n" -gt 0 ]; then
    sj_init || exit 0
    short=$(printf '%s\n' "$files" | sed "s|^$(sj_repo_root)/||" | head -25)
    sj_append "files" "hook" "Touched $n file(s)" "$short" || true
    touched=1
  fi
  rm -f "$buf/files.txt"
fi

# Nudge: substantive work but no model-authored reasoning this turn. Ships by
# design (it carries the "must not depend on the model remembering" requirement);
# tune the threshold, do not delete it.
if [ "$touched" -eq 1 ]; then
  f="$(sj_dir)/entries.txt"
  recent_agent=$(tail -40 "$f" 2>/dev/null | jq -rs '
    [ .[] | select(.source=="agent") ] | length' 2>/dev/null || echo 0)
  last_nudge=$(cat "$buf/last-nudge" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "${recent_agent:-0}" -eq 0 ] && [ $((now - last_nudge)) -gt 600 ]; then
    mkdir -p "$buf" 2>/dev/null
    echo "$now" > "$buf/last-nudge"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "Stop",
        additionalContext: "SESSION JOURNAL: you changed files but logged no reasoning. Add one entry describing WHY: session-journal add --kind decision --title \"...\" --body \"...\""
      }
    }'
    exit 0
  fi
fi
exit 0
```

- [ ] **Step 7: Make executable, run tests**

```bash
chmod +x programs/claude/hooks/session-journal-*.sh
bash tests/session-journal/run-tests.sh
```

Expected: `7 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add -A tests programs/claude/hooks
git commit -m "feat(session-journal): SessionStart/PostToolUse/SubagentStop/Stop hooks"
```

---

## Task 8: Skill, settings, and Nix wiring

**Files:**
- Create: `programs/claude/skills/session-journal/SKILL.md`
- Create: `programs/claude/session-journal-state`
- Modify: `programs/claude/settings.json`
- Modify: `home.nix`
- Modify: `programs/claude/README.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: session-journal
description: Use when working in a cmux workspace with journaling enabled — records the decisions and reasoning that scroll out of the chat into a per-workspace HTML page at localhost:7777, so a human can review many parallel sessions and question them later.
---

# session-journal

## What this is

Each cmux workspace has ONE HTML journal, browsable at http://localhost:7777.
Hooks automatically record mechanical facts (files touched, commits, subagent
reports). They cannot record *why* — that is your job.

The human runs many sessions in parallel and reads these pages instead of the
transcripts. Write for someone who will come back tomorrow and ask you to
justify a choice.

## When to log

| Log it | Don't log it |
|---|---|
| A decision between real alternatives | Routine file edits (hooks handle these) |
| Something that blocks you | Restating the user's request |
| A milestone that starts working | Narrating each step of a task |
| A discovered constraint that changes the approach | Anything you would not want to re-read |
| A rejected approach and why | Tool output |

Aim for a handful of substantial entries per session, not a running commentary.

## How

```bash
session-journal add --kind decision \
  --title "Used a mkdir mutex instead of flock" \
  --body "flock does not exist on macOS. mkdir is atomic on APFS. Verified with 8 concurrent writers."
```

Kinds: `decision`, `progress`, `blocker`, `milestone`, `question`.

Long bodies: `--body-stdin` reads stdin (bodies are truncated at 4096 bytes).

Other commands: `session-journal tail -n 20`, `path`, `status`.

## Rules

- **Title is a claim, not a topic.** "Chose X over Y because Z" beats "Discussed options".
- **The body carries the alternatives.** What you rejected is often the useful part.
- **Never read the whole journal.** Use `tail -n` if you need recent context.
- **Failing to log is not an error.** If disabled, the command exits 0 silently.

## Finding a journal

Markers are embedded in each page and its sidecar:

```bash
grep -l "<workspace-or-session-uuid>" ~/html-pages/*-session-*/meta.json
grep -l 'session-journal:workspace-id" content="<uuid>' ~/html-pages/*-session-*/index.html
```
```

- [ ] **Step 2: Create the state seed**

```bash
printf 'DISABLED\n' > programs/claude/session-journal-state
```

- [ ] **Step 3: Register the hooks**

Edit `programs/claude/settings.json`. **The `Stop` array already contains the
beep hook — append, do not replace.** Resulting `hooks` object:

```json
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-journal-start.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "AskUserQuestion",
        "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/tool-after.sh" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash",
        "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-journal-tool.sh" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-journal-subagent.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/tool-after.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-journal-stop.sh" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/tool-after.sh" } ] }
    ]
  },
```

Verify the beep survived:

```bash
jq '.hooks.Stop | length' programs/claude/settings.json      # → 2
jq -r '.hooks.Stop[].hooks[].command' programs/claude/settings.json | grep -c tool-after  # → 1
```

- [ ] **Step 4: Wire up Nix**

In `home.nix`, after `ensureHtmlPagesDir`, add the mutable-copy activation.
`beep-state` is symlinked into the read-only store, so `echo > ~/.claude/beep-state`
writes into the nix store — this avoids inheriting that bug:

```nix
  # Session journal toggle. Installed as a MUTABLE COPY (not a home.file symlink)
  # so `claude-journal-on/off` can actually write to it. A symlink would point
  # into the read-only nix store. Seeded once; never overwritten afterwards.
  home.activation.installSessionJournalState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    STATE="$HOME/.claude/session-journal-state"
    if [ ! -f "$STATE" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.claude"
      $DRY_RUN_CMD cp ${./programs/claude/session-journal-state} "$STATE"
      $DRY_RUN_CMD chmod 644 "$STATE"
    fi
  '';
```

Add the shell helpers next to the `claude-beep-*` functions (~line 429):

```bash
      # Session journal control (per-cmux-workspace HTML log at localhost:7777)
      claude-journal-on() {
        echo "ENABLED" > ~/.claude/session-journal-state
        echo "Session journal enabled"
      }
      claude-journal-off() {
        echo "DISABLED" > ~/.claude/session-journal-state
        echo "Session journal disabled"
      }
      claude-journal-status() {
        local s; s=$(cat ~/.claude/session-journal-state 2>/dev/null || echo "DISABLED (unset)")
        echo "Session journal: $s"
        command -v session-journal >/dev/null && session-journal status
      }
```

The hooks directory is already symlinked wholesale (`home.nix:143-146`), so the
new scripts and the `session-journal` CLI are installed automatically. Add
`~/.claude/hooks` to PATH so the CLI is callable by name:

```nix
    # session-journal CLI lives alongside the hooks that use it.
    home.sessionPath = [ "$HOME/.claude/hooks" ];
```

- [ ] **Step 5: Verify the build**

```bash
nix flake check --no-build --impure
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add -A programs/claude home.nix
git commit -m "feat(session-journal): skill, hook registration, nix wiring"
```

---

## Task 9: Live verification (the real gate)

Everything so far is tested in a sandbox. This task validates the assumptions
that could not be tested offline: R1 (cmux hook composition), R2 (subagent
payload shape), R8 (no reload storm), R10 (gallery visibility), R11 (beep alive).

- [ ] **Step 1: Apply the configuration**

```bash
homeswitch
```

- [ ] **Step 2: Enable and restart Claude Code**

```bash
claude-journal-on
claude-journal-status
```

Then start a NEW Claude Code session (hooks load at startup).

- [ ] **Step 3: Verify SessionStart fired (R1)**

```bash
session-journal path
session-journal tail -n 5
```

Expected: a `session` entry. **If empty, R1 has materialized** — cmux's own hooks
are overriding ours. Diagnose with `claude --debug` and look for hook execution
lines; the fallback is to chain our script from cmux's hook.

- [ ] **Step 4: Verify gallery visibility (R10)**

```bash
open http://localhost:7777
```

Expected: an entry titled `<repo> · <branch>` with style "Session journal".
If missing, check `index.html` exists and is readable.

- [ ] **Step 5: Verify no reload storm (R8)**

Open the gallery in one tab and the journal in another. In a third terminal:

```bash
for i in 1 2 3 4 5; do session-journal add --kind progress --title "storm test $i"; sleep 1; done
```

Expected: the journal page updates within ~3s **without a full reload**, and the
gallery tab does **not** flicker/reload. A reloading gallery means `entries.txt`
somehow entered the watcher's filter.

- [ ] **Step 6: Capture the real SubagentStop payload (R2)**

Temporarily add payload capture at the top of `session-journal-subagent.sh`:

```bash
printf '%s' "$payload" > /tmp/subagent-payload.json
```

Dispatch any subagent, then:

```bash
jq . /tmp/subagent-payload.json
```

Record the actual field carrying the final report and fix the `jq` fallback chain
if none of `.result/.final_message/.output/.response` matched. Then remove the
capture line and re-run the test suite.

- [ ] **Step 7: Verify the beep still works (R11)**

Confirm the beep still fires on Stop as before. If silent:

```bash
jq -r '.hooks.Stop[].hooks[].command' ~/.claude/settings.json
```

Both `tool-after.sh` and `session-journal-stop.sh` must be listed.

- [ ] **Step 8: Verify multi-workspace isolation**

Open a second cmux workspace on a different repo, let it write, then:

```bash
ls -d ~/html-pages/*-session-*
```

Expected: two directories with different `<wsid8>` suffixes.

- [ ] **Step 9: Verify disable works mid-session**

```bash
claude-journal-off
session-journal add --kind progress --title "must not appear"
session-journal tail -n 3    # entry absent
claude-journal-on
```

- [ ] **Step 10: Commit any fixes**

```bash
git add -A
git commit -m "fix(session-journal): corrections from live verification"
```

---

## Task 10: Documentation and PR

- [ ] **Step 1: Document in `programs/claude/README.md`**

Add a `## Session Journal` section covering: what it does, `claude-journal-on/off/status`,
where journals live, the per-repo `.no-session-journal` opt-out, and the plaintext
caveat for client repos.

- [ ] **Step 2: Full test run**

```bash
bash tests/session-journal/run-tests.sh
nix flake check --no-build --impure
```

Expected: all tests pass, flake check clean.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin <branch>
gh pr create --title "feat: per-workspace session journals" --body "..."
```

PR body must state: what it does, that it is **opt-in** (`claude-journal-on`),
the plaintext-storage caveat, and the R1/R2 verification results from Task 9.

---

## Verification checklist

- [ ] `bash tests/session-journal/run-tests.sh` — all pass
- [ ] `nix flake check --no-build --impure` — clean
- [ ] Journal appears at localhost:7777 (R10)
- [ ] Appends do not reload the gallery tab (R8)
- [ ] Subagent entries appear without instructing the subagent (R2)
- [ ] The beep still fires on Stop (R11)
- [ ] `claude-journal-off` stops writes mid-session
- [ ] Two workspaces produce two journals
- [ ] Disabled is the default on a fresh install
