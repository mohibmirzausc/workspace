# Porting Claude's MCP servers to Pi

Pi has **no MCP support**, by design: *"No MCP. Build CLI tools with READMEs,
or build an extension that adds MCP support."* So the port is not a config
translation — each service has to be re-homed onto whatever costs least.

The goal is functional parity at lower token cost. The rule of thumb that
falls out of the measurements below:

> **REST API with a token → CLI + skill. Remote OAuth service → MCP adapter.
> Plain files → nothing at all.**

## Why bother: MCP tool definitions are not free

An MCP server's tool definitions are sent on **every request**, whether or
not the service is used. Counted from a live Claude session:

| Server | Tools | Est. tokens/request |
|---|---|---|
| `shortcut` | 45 | ~11k–29k |
| `playwright` | 26 | ~7k–17k |
| `MCP_DOCKER` (gateway) | 20 | ~5k–13k |

A skill costs a few hundred tokens and is read **only when relevant**.
Upstream measured the same effect: Playwright's MCP server at 13.7k tokens
versus 225 tokens for an equivalent CLI + README.

## Status per service

| Service | Auth | Approach | Status |
|---|---|---|---|
| `shortcut` | API token in sops | `sc` CLI + skill | ✅ **done** |
| `MCP_DOCKER` → obsidian | none (local files) | nothing needed | ✅ **no work** |
| `playwright` | none | **deferred** — keep MCP for now | ⏸️ parked |
| `agent-mail` | bearer in sops | `curl` wrapper + skill | ⬜ todo |
| `notion` | **OAuth only** | `pi-mcp-adapter` | ⬜ todo |
| `slack` | **OAuth only** | `pi-mcp-adapter` | ⬜ todo |

### shortcut → `sc` CLI ✅

Done. `programs/agents/tools/sc.sh` + `skills/shortcut/`. Replaces 45 tool
definitions with one skill.

The Shortcut REST API takes a plain `Shortcut-Token` header, and the token is
already in sops. `sc` decrypts it **at call time**, so — unlike the Claude
side, which writes it into `~/.claude.json` — no plaintext token is on disk.

Verified: every read subcommand against the live API; the nix-built binary
under `env -i` (proving `runtimeInputs`); and Pi, given only the skill,
correctly answering "how many stories do I have open" by discovering and
running `sc`.

### MCP_DOCKER → nothing needed ✅

`MCP_DOCKER` is a *gateway* proxying other servers. Inspection shows it is
serving **Obsidian** (11 `obsidian_*` tools) plus 9 gateway-management tools.

The vaults are ordinary git repos of Markdown under `~/src/` (e.g.
`obsidian-golden-path`, `notes-layout`). Pi's built-in `read`/`write`/`edit`/
`bash` already handle those natively, so all 20 tool definitions are
redundant — Pi only needs to know the path, which
`skills/obsidian-vault-engineering/` covers.

**Do not port this.** Deleting it from Pi's world is a pure win.

### playwright → parked ⏸️

26 tool definitions, and upstream's own headline example — but **deferred by
decision**, not by analysis.

Unlike Shortcut, this is not a thin REST wrapper. The MCP server owns a
browser lifecycle, and a CLI replacement has to own it too: a short-lived CLI
process cannot keep a browser alive between invocations without extra
machinery (an independently-launched Chrome on a fixed debugging port, plus
session/teardown handling). That is a real amount of moving parts for a tool
that is used occasionally, and it means adding a browser-automation
dependency that is not currently installed.

Keep the Playwright MCP server for now. Revisit only if browser automation
becomes frequent enough that the per-request token cost actually bites.

### agent-mail → `curl` wrapper + skill ⬜

Local HTTP service at `127.0.0.1:8765`, bearer token in sops. A `curl`
wrapper is straightforward — same shape as `sc`.

Not yet done because the service is **not currently running** (connection
refused), so nothing can be verified end-to-end. Build it when the service
is up; shipping an untested wrapper would be worse than waiting.

### notion and slack → `pi-mcp-adapter` ⬜

**These must stay MCP.** Both are remote OAuth-backed servers:

- `notion` — `https://mcp.notion.com/mcp` returns **401** unauthenticated,
  and there is **no** Notion token in sops. OAuth-only.
- `slack` — `https://mcp.slack.com/mcp`, OAuth with a pre-registered
  `clientId`. `programs/sops/default.nix` already documents why: Slack's auth
  server advertises `registration_endpoint: null`, so dynamic client
  registration is unsupported.

Claude's OAuth sessions live in the **macOS Keychain**, not a file, so they
cannot be copied into Pi's config. Pi will need its own sign-in.

Use [`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter) (npm
`pi-mcp-adapter`, by the author of `pi-intercom`). It reads the **same
`mcpServers` schema** as Claude, so the existing `jq` patches in
`programs/sops/default.nix` port nearly verbatim — to
`~/.pi/agent/mcp.json`, with `auth: "oauth"` and `oauth.clientId`.

Reimplementing either service's OAuth as a CLI would be a large amount of
work to satisfy a philosophy. Not worth it.

## Blocked: the `interrupt` rewrite

Porting `skills/interrupt/SKILL.md` off MCP is the change that would let the
Shortcut MCP server be dropped. It is **blocked on a prior problem**: the
skill's hardcoded IDs do not exist in the workspace its own token reaches.

Checked 2026-09-22 against the `mo-tools` workspace, via both `sc` and the
Shortcut MCP server (they share one token, so both see the same data):

| Skill says | Reality |
|---|---|
| team `6940a30c-…` "Release Engineering" | no such team; the 3 that exist are all `archived: true` |
| workflow `500000566` | only `500000500` (Standard) exists |
| "Started" state `500000569` | `500000503` In Development / `500000504` Code Review |
| label `interrupts` | does not exist |

So **`interrupt` is already broken in Claude**, not merely unportable to Pi.
Its "verified against the Shortcut API on 2026-07-30" note has gone stale —
either the workspace was rebuilt or the skill was written against a different
one.

Rewriting it against `sc` is straightforward once the intended destination is
known, but that is a question for the skill's owner, not something to guess:
filing interrupts into the wrong team or state is worse than the current
failure, which is at least loud.

Until it is fixed, leave the Shortcut MCP server in place. Removing it would
change one broken path into a differently broken path.

## Secrets

Three separate layers; only the third is enforcement:

1. **Storage** — sops (`hm-secrets`). Solves at-rest. Says nothing about
   which agent may use what.
2. **Tool scoping** — `pi --tools` / `--exclude-tools` genuinely removes
   tools from the model's list; it cannot call what it cannot see. Verified:
   `pi --tools read` exposes exactly one tool.
3. **Enforcement** — the only layer that holds:
   - a `tool_call` handler returning `{ block: true, reason }` (what the
     installed `pi-guardrails` does), or
   - `nono` (already in `darwin.nix`), kernel-enforced via Seatbelt, which an
     agent cannot widen from the inside.

### The part that surprises people

**Any agent with `bash` already has every secret.** Verified — a Pi session
with `--tools bash` and no MCP servers configured:

```
$ pi --tools bash "Run: hm-secrets list"
FOSSA_API_KEY
GCAL_CLIENT_ID
GCAL_CLIENT_SECRET
```

So "agent A may use Notion, agent B may not" is **not enforceable by config**
while both have `bash`. Removing a tool hides a capability; it does not
protect the credential behind it.

The same agent without `bash` correctly reported it could not comply.

For per-agent access, separate by **profile** (distinct `HOME` /
`--session-dir` / project-local `.pi/`, each with its own `mcp.json` and tool
flags) and use `nono` for anything genuinely untrusted. A config that merely
*says* an agent lacks Notion is not evidence it cannot reach the token.
