# Intercom — agent-to-agent messaging for Pi

**Use the upstream package. Do not build our own.**

`pi-intercom` already exists, is on npm at **0.13.0**, and covers everything
we wanted plus several things we had not designed. This document is a usage
reference, not a spec.

- Package: `npm:pi-intercom` — <https://pi.dev/packages/pi-intercom>
- Source: <https://github.com/earendil-works/pi/tree/main/packages/coding-agent>
- Author: nicopreme · MIT

## Why we need it

Claude Code has `SendMessage`/`ListAgents`: sessions address each other by
name and a message lands in a running session's context. Pi ships no
equivalent and no sub-agents — the README is explicit that both are left to
extensions. `pi-intercom` is that extension.

## Install

```bash
pi install npm:pi-intercom
```

Restart Pi afterwards. The extension auto-connects to a local broker on
startup and registers its bundled skill.

Note this is an `npm:` package, not `git:` like
`mechanical-orchard/pi-guardrails`. Both land in `~/.pi/agent/` and both are
recorded in `~/.pi/agent/settings.json` under `packages`. That file is
written by pi at runtime, so installation is a CLI step and **not** declared
in Nix — same reasoning as the rest of Pi's mutable state, see
`programs/agents/README.md`.

## Addressing

This was our open question; upstream answers it three ways:

| Method | How |
|---|---|
| Explicit alias | `/alias <name>` |
| Session ID | collision-resistant stable identifier |
| Working directory | targets the sole peer in that cwd |

## The `intercom()` tool

| Action | Meaning |
|---|---|
| `list` / `list-cwd` | show active sessions |
| `send` | fire-and-forget |
| `ask` | send **and block for a reply** (10 min default timeout) |
| `reply` | answer an inbound `ask` |
| `pending` | show unresolved asks |
| `cancel` | retract a sent message |
| `status` | connection state and session count |

```javascript
intercom({ action: "send", to: "worker",  message: "..." })
intercom({ action: "ask",  to: "planner", message: "..." })
intercom({ action: "send", cwd: "/path",  message: "..." })
```

`ask`/`reply` is the notable addition over what we specified — blocking
request/response, not just one-way delivery.

Alt+M or `/intercom` opens a session-selection overlay.

With `pi-subagents` installed there is also `contact_supervisor()`, with
reasons `need_decision`, `interview_request`, `progress_update`.

## Configuration

`~/.pi/agent/intercom/config.json`:

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | master switch |
| `inboundTrigger` | — | auto-trigger policy: `always`, `replies`, `never` |
| `confirmSend` | `false` | confirmation dialog before sending |
| `replyHint` | `true` | append reply instructions to messages |
| `brokerCommand` | `npx` | custom broker executable |
| `status` | — | custom status suffix |

`inboundTrigger` is the setting to think about first. It decides whether an
inbound message interrupts the receiving agent. Start at `replies` — an
unsolicited peer message is rarely worth derailing a turn in progress, but an
answer you are blocked on is.

## Limitations

- **Same machine only** — local IPC (Unix sockets / Windows pipes).
- `list` shows only sessions that loaded `pi-intercom` and registered with
  the broker; a plain Pi session is invisible.
- No intercom transcript separate from session history.
- No attachment support in the compose overlay.
- Broker auto-spawns and exits after 5s idle; sessions auto-reconnect.
- Pi packages run with full system access — extensions execute arbitrary
  code. Review before installing, per Pi's own guidance.

## Not a Claude Code bridge

Intercom is Pi↔Pi only. Claude Code sessions cannot join a broker that speaks
Pi's IPC protocol.

If Claude↔Pi messaging is wanted later, that is a separate piece of work: a
file-backed bus both harnesses can read and write, since Claude sessions can
reach a file via Bash but not a Unix socket handshake. Worth doing only if the
need is real — do not build it preemptively.

## History

This file previously specified an Intercom we intended to build ourselves.
The design independently matched upstream on the essentials — point-to-point
by name, same-machine, and a policy for whether inbound messages interrupt —
so adopting `pi-intercom` costs nothing and gains `ask`/`reply`, `pending`,
`cancel`, the overlay, and the supervisor hook.
