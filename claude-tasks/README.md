# claude-tasks

A single-user task list with SMS reminders (with optional spam-mode escalation),
markdown journals per task, multiple views, natural-language quick-add, and a
Claude orchestrator that can pick up work attached to your tasks. Also exposed
as an MCP server so Claude Code can manage your tasks from any project.

## Architecture

```
packages/core         schema, types, RRULE, view filters, prompts
apps/server           Express + better-sqlite3 + reminder cron + Twilio + MCP + orchestrator
apps/web              Vite + React PWA (3-pane: views | list | detail+journal+claude)
apps/cli              `tk` thin client over the HTTP API
```

Single SQLite file (`tasks.db`). Server owns it; web/cli/mcp talk over HTTP/stdio.

## Getting started

```bash
pnpm install
cp .env.example .env       # fill in ANTHROPIC_API_KEY, TWILIO_*, OWNER_PHONE
pnpm db:push               # create the SQLite schema
pnpm server                # http://localhost:4000
pnpm web                   # http://localhost:5173 (PWA)
pnpm cli today             # CLI works once server is running
```

For SMS during development, expose the server with ngrok and set the Twilio
phone-number webhook for *Messaging → A Message Comes In* to:

    https://<your-tunnel>.ngrok.app/sms/inbound

## SMS commands

Replies (parsed by Claude — flexible wording works):

    done                    → marks the most-likely task done
    snooze 1h               → push reminder
    note: left voicemail    → append journal entry
    stop / ok               → ack (silences spam mode for now)
    list                    → today's tasks

## Wiring Claude Code as an MCP client

Add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "claude-tasks": {
      "command": "node",
      "args": ["--import", "tsx", "/abs/path/to/apps/server/src/mcp.ts"],
      "env": { "DB_PATH": "/abs/path/to/tasks.db" }
    }
  }
}
```

Then from any Claude Code session you can do:

    /mcp claude-tasks tasks_quickadd utterance="tomorrow 9am gym"
    /mcp claude-tasks tasks_add_claude_todo task_id=01HX… instruction="draft email"

## What lives where (for the orchestrator)

- A "Claude todo" is a row in `claude_todos` keyed to a task. Insert via
  `POST /tasks/:id/claude` (web button) or `tk claude <id> <instruction>` (CLI)
  or the MCP `tasks_add_claude_todo` tool.
- The orchestrator loop drains queued todos every 5s and runs them with Opus,
  passing the task's notes + journal as context. Tools available to the Claude
  call: `append_journal`, `update_task`. Result lands in the journal.

## v1 scope (explicitly done / not done)

Done:
- Tasks, journal, RRULE recurrence, multiple views
- Markdown notes + per-task journal
- Twilio SMS out (escalating "spam mode") + Twilio inbound webhook
- Claude-parsed quick-add and SMS reply parsing
- Claude orchestrator + MCP server
- React PWA shell + CLI

Not done (v2):
- Web Push (alongside SMS)
- Daily standup digest cron
- Telegram bot channel
- Calendar/Kanban/Matrix views (the data model supports them; UI shows a list)
- Agent-runner for `claude_todos` that need git-worktree side-effects
