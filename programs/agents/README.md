# Agent configuration (harness-neutral)

Single source of truth for agent content that is **not** specific to one
harness. Claude Code and Pi both read the directories here, via symlinks
declared in `home.nix`.

Harness-*specific* config stays in its own directory:
`programs/claude/` holds Claude's `settings.json`, hooks and beep-state.

## Layout

| Directory | Claude Code       | Pi                   |
|-----------|-------------------|----------------------|
| `skills/` | `~/.claude/skills`   | `~/.pi/agent/skills`  |
| `prompts/`| `~/.claude/commands` | `~/.pi/agent/prompts` |

Same content, different names per harness — Claude calls them "commands",
Pi calls them "prompt templates". Both are plain Markdown with optional
`name`/`description` frontmatter, so one file serves both.

Skills follow the [Agent Skills standard](https://agentskills.io), which both
harnesses implement: a directory containing `SKILL.md` with `name` and
`description` frontmatter.

## Why symlinks to one directory, not two copies

Two copies drift. The formats are already compatible, so there is nothing to
translate — verified against pi 0.85.1 before adopting this layout:

```bash
pi --skill           programs/agents/skills   # skill discovered and listed
pi --prompt-template programs/agents/prompts  # templates loaded
pi --prompt-template programs/agents/prompts "/grill-me"   # expands and runs
```

Claude skills and commands load into Pi unmodified, with no format changes.
The third check is the end-to-end one: invoking the real ported `/grill-me`
as a slash command expanded its body and the model acted on it, so these are
working commands under Pi and not merely files Pi tolerates.

## Frontmatter is required

Every `SKILL.md` needs YAML frontmatter with `name` and `description`:

```markdown
---
name: my-skill
description: Use when ...
---
```

Pi enforces this and silently **skips** a skill without it — no warning, the
skill is simply absent. Claude Code is more lenient and will list a skill
that has none, so a skill can work in Claude and be invisible in Pi.

The `nelson` skill hit exactly this — it worked in Claude and was silently
missing in Pi, which is how the rule was discovered. (That skill has since
been removed as unused.) To audit the rest:

```bash
for d in programs/agents/skills/*/; do
  head -1 "$d/SKILL.md" | grep -q '^---$' || echo "NO FRONTMATTER: $(basename $d)"
done
```

## Adding a skill or prompt

Drop it in `skills/<name>/SKILL.md` or `prompts/<name>.md`, then run
`homeswitch`. Both harnesses pick it up — no per-harness step.

Prompts may use `{{PLACEHOLDER}}` variables; this is Pi's prompt-template
syntax and several existing prompts (`teach.md`, `ultraimprove.md`) already
use it.

## Caveat: content written for one harness

The formats are portable; the *contents* are not always. A skill or prompt
that references Claude-only machinery — the `Task`/`Agent` tool,
`TeammateTool`, plan mode — loads cleanly in Pi but then instructs the model
to use tools that do not exist there.

Pi deliberately ships no sub-agents or plan mode; those are left to
extensions.

`prompts/agentswarm.md` was removed for exactly this: it was wholly about
orchestrating Claude's `TeammateTool`/`Task` system, so under Pi it was not
merely useless but actively misleading.

`prompts/review-pr` still has one such line — it asks for a `pr-deep-review`
sub-agent via the Task tool. The rest of it is harness-neutral, so it is kept
as-is; under Pi the model should review serially instead of fanning out.

To find others:

```bash
grep -rln 'TeammateTool\|Task tool\|subagent_type\|EnterPlanMode' programs/agents/
```

## Pi-specific notes

Pi's binary comes from the `pi-coding-agent` brew in `darwin.nix`
(homebrew-core, with `autoUpdate`/`upgrade` on, so it tracks releases).

`~/.pi/agent/` runtime state is deliberately **not** managed by Nix:

- `settings.json` — Pi writes theme, `lastChangelogVersion`, and the default
  model saved with Ctrl+S in the model picker
- `auth.json`, `models-store.json`, `trust.json` — credentials, model catalog
  cache, per-project trust decisions

Symlinking any of these into the read-only Nix store would make Pi fail on
write, the same `EACCES` trap documented for Claude plugins in
`programs/claude/README.md`.

Pi packages (the analogue of Claude plugins) install to `~/.pi/agent/git/` or
`~/.pi/agent/npm/` and are listed in `settings.json` under `packages`. Because
that file is mutable, packages are installed with the CLI rather than declared
in Nix:

```bash
pi install git:github.com/mechanical-orchard/pi-guardrails@v0.15.0
pi list
```
