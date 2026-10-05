# Porting Claude's MCP servers to Pi

> **Changed in Pi 1.0 (2026-10-05).** Pi now has a **built-in MCP client** —
> `pi mcp add/list/login/logout/remove`, with OAuth sign-in handled natively.
> Most of this document was written when Pi had no MCP at all, and the work it
> describes is still the right call; see *Does 1.0 undo any of this?* below
> before concluding otherwise.

Pi used to have **no MCP support**, by design: *"No MCP. Build CLI tools with
READMEs, or build an extension that adds MCP support."* So the port was not a
config translation — each service had to be re-homed onto whatever costs least.

The goal is functional parity at lower token cost. The rule of thumb that
falls out of the measurements below:

> **REST API with a token → CLI + skill. Remote OAuth service → MCP, in
> codemode. Plain files → nothing at all.**

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
| `shortcut` | API token in sops | `sc` CLI + skill | ✅ **done, MCP removed** |
| `MCP_DOCKER` → obsidian | none (local files) | nothing needed | ✅ **no work** |
| `playwright` | none | **deferred** — keep MCP for now | ⏸️ parked |
| `agent-mail` | bearer in sops | `curl` wrapper + skill | ⬜ todo |
| `notion` | **OAuth only** | built-in MCP, codemode | ✅ configured, needs sign-in |
| `slack` | **OAuth only** | built-in MCP, codemode | ✅ configured, needs sign-in |

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

### The saving is now actually realized

Adding `sc` did not by itself reduce anything: the cost of an MCP server is
its *tool definitions*, sent every request whether or not the service is
used. While `mcpServers["shortcut"]` remained in `~/.claude.json`, Claude
paid the full ~11k–29k tokens **and** had the CLI — two paths to the same
service, no saving.

`programs/sops/default.nix` no longer writes that entry, and its activation
patch removes any left behind by an earlier run (top level and project
level). Verified idempotent against fixtures with: no `mcpServers` key, no
`shortcut` entry, an empty object, and a null project value.

Side effect worth naming: the Shortcut API token is no longer written in
plaintext into `~/.claude.json` at all. `sc` decrypts it from sops at call
time.

The `shortcut_api_token` secret **stays in the sops store** — `sc` reads it.
Only the MCP registration is gone.

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

### notion and slack → built-in MCP, in codemode ✅

**These must stay MCP.** Both are remote OAuth-backed servers:

- `notion` — `https://mcp.notion.com/mcp` returns **401** unauthenticated,
  and there is **no** Notion token in sops. OAuth-only.
- `slack` — `https://mcp.slack.com/mcp`, OAuth with a pre-registered
  `clientId`. `programs/sops/default.nix` already documents why: Slack's auth
  server advertises `registration_endpoint: null`, so dynamic client
  registration is unsupported. Notion supports dynamic registration, so it
  needs neither a client id nor a fixed callback port.

Reimplementing either service's OAuth as a CLI would be a large amount of
work to satisfy a philosophy. Not worth it.

Pi 1.0 made this easy — **no adapter needed**. An earlier draft of this
document recommended `pi-mcp-adapter`; that is now obsolete, and it was never
installed. Both servers are registered by `pi-bootstrap`:

```bash
pi mcp add slack --url https://mcp.slack.com/mcp \
  --oauth-client-id 1601185624273.8899143856786 --oauth-callback-port 3118
pi mcp add notion --url https://mcp.notion.com/mcp
```

Slack also needs `oauth.callbackUrl: "http://localhost:3118/callback"`. The
client id is Claude's Slack app, which registers that exact URI, while
`--oauth-callback-port` alone makes Pi send `http://127.0.0.1:3118/callback`.
Slack rejects the mismatch ("redirect_uri did not match any configured
URIs"). `pi mcp add` has no flag for `callbackUrl`, so `pi-bootstrap` sets it
with `jq` right after adding the server.

The resulting `~/.pi/agent/mcp.json` uses nearly the same `mcpServers` schema
as Claude, so the two configs stay readable side by side.

**`--exposure codemode` is the default, and it is the whole point.** Tool
definitions are *not* injected into the system prompt; Pi loads them on
demand. That keeps the per-request cost near zero rather than the ~11k–29k
tokens Claude pays for the same servers whether or not they are used. The
other modes are `direct` (Claude-like, always in the prompt), `deferred`
(names up front, schemas on demand) and `hidden`.

A consequence worth remembering: **codemode tools do not appear in a tool
list.** "I don't see a Slack tool" is not evidence anything is broken — test
by asking Pi to actually use it.

#### Sign-in is the one manual step

Claude's OAuth sessions live in the **macOS Keychain** (item
`Claude Code-credentials`, an `mcpOAuth` object keyed `slack|<hash>`), in a
Claude-specific schema. They cannot be copied into Pi. Pi needs its own:

```bash
pi mcp login slack
pi mcp login notion
```

This opens a browser, so it is deliberately **not** scripted in
`pi-bootstrap`. `pi mcp list` exits non-zero while any server still needs
sign-in, which makes it a usable check.

Unlike Claude, Pi stores the resulting tokens **on disk**, at
`~/.pi/agent/mcp-auth.json`, created `0600` in a `0700` directory (verified in
`dist/core/auth-storage.js`). Nothing secret is written by `pi mcp add` —
`mcp.json` holds only URLs and a public client id, and is world-readable.

## Does Pi 1.0 undo any of this?

Mostly **no**, and it is worth being precise about why, because "Pi has MCP
now" is an easy reason to throw away work that is still earning its keep.

The argument for a CLI was never *"Pi cannot do MCP."* It was **token cost**:
an MCP server's tool definitions ship on every request, used or not. Having a
built-in client does not change that arithmetic for `direct` exposure.

| | Keep as-is | Why |
|---|---|---|
| `sc` CLI | ✅ keep | Replaces 45 tool definitions. A plain-token REST API is still cheaper and simpler as a CLI, and it keeps the token off disk. |
| `MCP_DOCKER`/Obsidian | ✅ still delete | Plain Markdown files. MCP adds nothing a built-in `read` cannot do. |
| `agent-mail` | ✅ still a CLI | Bearer token in sops, local HTTP. Same shape as `sc`. |
| `playwright` | 🤔 reconsider | The one genuine candidate. It was parked because a CLI would have to own a browser lifecycle; MCP in codemode sidesteps that at low cost. |
| `notion`, `slack` | ✅ now MCP | Always had to be. 1.0 is what made it possible without an adapter. |

The honest summary: 1.0 **unblocked** the two services that were stuck, and
makes Playwright worth revisiting. It does not argue for undoing the CLIs.

What *should* be retired is the blanket claim "Pi has no MCP." It was true,
it shaped every decision here, and as of 1.0 it is false.

## Resolved: the last MCP callers are gone

Dropping the Shortcut MCP server was blocked on two files that called it
directly. Both are now clear (2026-09-23):

| File | Was | Now |
|---|---|---|
| `skills/interrupt/SKILL.md` | `mcp__shortcut__*` + `mcp__plugin_slack_slack__*` | **deleted** — obsolete |
| `prompts/review-pr` | `mcp__shortcut__stories-get-by-id` | `sc story <id>` |

`interrupt` turned out to be broken before any of this work: its hardcoded
IDs did not exist in the workspace its own token reaches. Checked against
`mo-tools` through both `sc` and the Shortcut MCP server (they share a token,
so both see the same data):

| Skill said | Reality |
|---|---|
| team `6940a30c-…` "Release Engineering" | no such team; the 3 that exist are archived |
| workflow `500000566` | only `500000500` (Standard) |
| "Started" state `500000569` | `500000503` / `500000504` |
| label `interrupts` | does not exist |

Rather than guess at replacements it was removed as obsolete.

`review-pr` only ever needed "fetch a story by id", which `sc story` does.
Verified the response carries everything it reads — name, description,
`app_url`, comments, tasks, `story_links`.

**`grep -rln 'mcp__' programs/agents/` now returns nothing.** The Shortcut MCP
server can be removed from `~/.claude.json` whenever you want the ~11k–29k
tokens per request back; nothing in the shared content depends on it.

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
