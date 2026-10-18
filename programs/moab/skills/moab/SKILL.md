---
name: moab
description: "Use when writing, editing, validating or reasoning about moab DOT pipelines (Mechanical Orchard's pipeline runner whose steps are Claude Code / Codex agents), or answering questions about moab pipeline syntax, sandbox grants, goal gates or why a run behaved a certain way. Points at moab's own authoring skills for the installed version, plus the local rules that override them. To actually run a pipeline, use the moab-worker skill."
---

# moab: pipeline authoring

moab ships its own authoring skills. Read them from the moab source **at the tag that matches the installed moab**, rather than from a copy that could be stale. This skill tells you how, and lists the local rules that **override** what they say.

## Read moab's skills for the installed version

```bash
V=$(moab --version | awk '{print $2}')              # e.g. 0.39.0 ("moab 0.39.0 (3ee9971)")
git -C ~/src/moab rev-parse -q --verify "v$V" >/dev/null || git -C ~/src/moab fetch -q --tags
git -C ~/src/moab ls-tree -r --name-only "v$V" skills/
git -C ~/src/moab show "v$V:skills/moab--create-pipeline/SKILL.md"
```

| moab skill | Use it to |
|---|---|
| `moab--create-pipeline` | write a new pipeline from scratch |
| `moab--edit-pipeline` | change an existing pipeline |
| `moab--validate-pipeline` | fix what `moab pipeline validate` reports |
| `moab--kb` | answer questions: grammar, attributes, topologies, loops (`pipeline-reference.md`, `loop-patterns.md`, `validate-prompt.md`) |
| `moab--pipeline-run-prepare` | check a pipeline for MaaS (production). Not needed for local runs. |

**Two quirks of reading them from source:**
- They are templates. Read `{{exe_name}}` as `moab`.
- They point at each other with relative paths such as `../moab--kb/pipeline-reference.md`. Those resolve under `skills/`, so run `git -C ~/src/moab show "v$V:skills/moab--kb/pipeline-reference.md"`.

**Without the `~/src/moab` checkout:**
```bash
gh api "repos/mechanical-orchard/moab/contents/skills/moab--kb/SKILL.md?ref=v$V" -q .content | base64 -d
```

## Local rules (they win over moab's skills)

### Running and safety
- **Always sandboxed.** Every agent node needs a `sandbox.fs` grant covering the folder the pipeline runs from (`ro:.` or `rw:.`). Credentials only come through `sandbox.secrets`: `anthropic` for `claude-code`, `openai` for `codex`. Never `github` or `gitlab`: pipelines commit locally and the operator pushes. Runs start with `--sandbox nono`. The memory extension blocks a `moab run start` without it, and `moab-run` always adds it.
- **Grants resolve against the pipeline file's folder.** When `moab-run` starts a run, that folder is the repo clone. Never write absolute grants or grants with `..`; `moab-run` refuses them.
- **No nested writable grants.** `rw:.` together with `rw:./out` fails when the run starts (`sandbox_grant_integrity`), although `moab pipeline validate` passes it. When agents commit, use one `rw:.` grant. Otherwise use `ro:.` plus `rw:./out`.
- **Writable paths must exist before the run.** `moab-run` creates the ones the pipeline names.
- **Tool nodes (`shape=parallelogram`) and hooks are NOT sandboxed.** They run on the host with your file access, and they can see the API key. Put only commands you wrote and trust there. Never run a pipeline you didn't write or review.

### Making a run's result checkable
- **Give the work a goal gate.** moab's `Success` only means the pipeline reached its end. Mark the node that must succeed with `goal_gate=true`.
- **Have agents commit their changes**, or write to an `out/` folder, so `moab-run collect` can see what was produced.
- **Prefer prompt files** (`prompt_file="prompts/<node>.md"`) for prompts longer than a line. `moab-run` copies them into the clone with the pipeline.

### Cost and models
- **Pick cheap models for simple steps:** `model="haiku"` (family aliases such as `haiku`, `sonnet` and `opus` survive upgrades).
- **The default is `reasoning_effort="high"`.** Lower it where depth doesn't matter.
- **Even a trivial claude-code step costs** about 70k–300k tokens, mostly cache reads of its system prompt.

### Where pipelines live
- moab source and docs are **confidential**. Never copy them into the memory repo or the ledger, which live on Mohib's personal GitHub.
- Pipelines **meant to be shared** may be kept in `~/src/memory/pipelines/<project>/NN-name.dot` (with `prompts/`).
- One-off pipelines go in a scratch folder **outside the target repo**.
