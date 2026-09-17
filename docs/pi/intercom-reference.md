# Intercom — a Pi package for agent-to-agent messaging

Status: **reference / not yet implemented.** This document defines what
Intercom is and how it hangs off Pi's extension API, so the implementation PR
has something to build against. Every API call cited here was checked against
pi **0.85.1** (`@earendil-works/pi-coding-agent` typings) — see
[Verified API surface](#verified-api-surface).

## Problem

Claude Code has `SendMessage` / `ListAgents`: sessions address each other by
name and a message lands in a running session's context. Pi has no equivalent.
Pi ships no sub-agents by design — the README is explicit that sub-agents and
plan mode are left to extensions.

Intercom supplies the missing piece: **let one agent session send a message to
another and have it arrive in that session's context.**

Scope for v1 is deliberately small — "we only want it to work regularly at the
moment". Delivery between sessions, nothing more. Spawning, supervision trees
and delegation are explicitly out of scope; see [Non-goals](#non-goals).

## Terminology

Pi calls these **packages**, not plugins — a `package.json` carrying a `pi`
key that bundles `extensions/`, `skills/`, `prompts/` and `themes/`. Installed
with `pi install git:github.com/<org>/<repo>@<tag>`. It is the structural
analogue of a Claude plugin.

`mechanical-orchard/pi-guardrails` is an existing MO package in exactly this
shape and is the template to copy.

## Design

A **file-backed message bus.** No daemon, no port, no broker.

```
~/.intercom/
  agents/<name>.json      # registration: name, pid, cwd, session id, last seen
  inbox/<name>.jsonl      # append-only; one JSON message per line
```

Two halves inside one extension:

1. **Outbound** — a `send_message` tool the model calls. Appends a line to the
   recipient's inbox. A `list_agents` tool reads `agents/` so the model can
   discover who is reachable.
2. **Inbound** — a watcher on the local inbox. On a new line, inject it into
   this session's context.

Delivery uses `pi.sendUserMessage(...)`, which always triggers a turn, or
`pi.sendMessage(...)` for a custom message type that can be rendered
distinctly in the transcript. Both accept `deliverAs` to control what happens
when the agent is mid-stream:

| `deliverAs`  | Behaviour                                    |
|--------------|----------------------------------------------|
| `"steer"`    | interrupt the current turn with the message   |
| `"followUp"` | queue until the current turn finishes         |
| `"nextTurn"` | hold until the next turn begins (`sendMessage` only) |

**Default to `followUp`.** Steering mid-turn derails work in progress; a
message from a peer is rarely urgent enough to justify that. Reserve `steer`
for an explicit `urgent: true` flag on the send.

### Why a file bus

- Works with **zero** coordination between processes that never knew about
  each other.
- Survives session restarts — an inbox is just a file.
- Inspectable and debuggable with `cat`.
- Crucially, **it is not Pi-specific.** Claude Code sessions can read and
  write the same files via Bash, so the same bus can bridge both harnesses
  later without redesign. (Bridging is not in v1, but the format shouldn't
  foreclose it.)

Registration must be refreshed and stale entries reaped, or `list_agents`
accumulates dead sessions. Register on `session_start`, refresh on
`agent_settled`, and treat an entry whose pid is gone as dead.

### Message format

One JSON object per line. Keep it small and boring:

```json
{
  "id": "01a0acb0-...",
  "from": "reviewer",
  "to": "builder",
  "ts": "2026-09-16T00:00:00.000Z",
  "urgent": false,
  "body": "The auth test is failing on main, not your branch."
}
```

## Sketch

```typescript
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function intercom(pi: ExtensionAPI) {
  pi.registerTool({
    name: "send_message",
    label: "Send message to agent",
    description: "Send a message to another running agent session by name.",
    promptSnippet: "Message another agent session by name.",
    parameters: /* { to, body, urgent? } */ undefined as never,
    async execute(_id, params) {
      // append one JSON line to ~/.intercom/inbox/<to>.jsonl
    },
  });

  pi.registerTool({ name: "list_agents", /* reads ~/.intercom/agents/ */ });

  pi.on("session_start", async () => {
    // register this session, then watch ~/.intercom/inbox/<me>.jsonl
    // on new line:
    //   pi.sendUserMessage(`[intercom] from ${m.from}: ${m.body}`, {
    //     deliverAs: m.urgent ? "steer" : "followUp",
    //   });
  });

  pi.on("agent_settled", async () => {
    // refresh registration heartbeat; drain anything buffered while busy
  });
}
```

## Verified API surface

Checked against pi 0.85.1 typings
(`dist/core/extensions/types.d.ts`) — these exist and have these shapes:

- `pi.registerTool({ name, label, description, promptSnippet, parameters, execute })`
- `pi.registerCommand(name, options)` — for `/intercom` status
- `pi.sendUserMessage(content, { deliverAs: "steer" | "followUp", expandPromptTemplates? })`
  — "Send a user message to the agent. Always triggers a turn."
- `pi.sendMessage(message, { triggerTurn?, deliverAs: "steer" | "followUp" | "nextTurn" })`
- `pi.appendEntry(customType, data)` — persist state in the session
- `pi.registerMessageRenderer(customType, renderer)` — render inbound
  messages distinctly in the transcript
- `pi.on("session_start" | "agent_settled" | "agent_end", handler)`
  — `agent_settled` fires "after an agent run has fully settled and no
  automatic retry, compaction, or queued continuation will run", which is the
  right moment to deliver without racing the agent loop

## Open questions

1. **Naming.** Who assigns a session's name? `pi --name/-n` sets a session
   display name and `pi.getSessionName()` reads it — probably the answer, with
   a fallback derived from cwd for unnamed sessions. Collisions need a rule.
2. **Watch mechanism.** `fs.watch` is cheap but flaky across platforms;
   polling on `agent_settled` plus a timer is dumber and more reliable. Start
   with polling.
3. **Delivery while idle.** A session sitting at an empty prompt is not
   running a turn. `sendUserMessage` triggers one — confirm that is acceptable
   UX and not a surprise wake-up.
4. **Trust.** Any local process can write to an inbox. Acceptable for
   same-user sessions on one machine; revisit before anything crosses a
   machine boundary. Note that Pi packages run with full system access.
5. **Where it lives.** In-repo under `programs/pi/intercom/` versus its own
   `mechanical-orchard/pi-intercom` repo installed with `pi install git:...`.
   Deferred — prototype first, extract if it proves useful.

## Non-goals

- Spawning or supervising child agents.
- Cross-machine messaging.
- Replacing Claude Code's `Agent`/`Task` tooling.
- A general pub/sub bus. Point-to-point by name is enough for v1.
