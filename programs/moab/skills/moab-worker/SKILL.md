---
name: moab-worker
description: "Use when a task should be done by running a moab pipeline, i.e. handing a repeatable or multi-step coding job to sandboxed Claude Code / Codex agents, or when asked to run, monitor, debug, rerun or collect a moab run. Covers the whole loop with moab-run: spec, pipeline, validate, start in a throwaway clone with a budget, watch, diagnose, fix and rerun, collect and verify, deliver, clean up, and record lessons. Work machines only."
---

# moab-worker: get work done with a moab pipeline

In this loop **you are the operator; the pipeline's agents do the work.**
- You write the spec and the pipeline, start it, watch it, judge the result and deliver it.
- The agents work sandboxed, in a throwaway clone of the repo.
- Pipeline agents never write to the memory system. You record what matters.

**Use moab when the job is worth it:** repeatable work, multi-step work with checks between steps, or the same change across many units. A small one-off edit is cheaper to do yourself. Even a trivial agent step costs about 70k–300k tokens.

**The tools:**
- `moab-run` starts, checks and collects runs. `moab-run --help` lists the commands; the docs are `~/src/memory/docs/moab-run.md`.
- The `moab` skill covers pipeline syntax and the local authoring rules. Read it before writing a pipeline.

## The loop

### 1. Spec: decide what "done" means before writing anything
Write down:
- the goal
- the input (repo and base ref)
- **checkable done-criteria**: the files that must exist, the tests that must pass, and the commits expected

Those criteria become the pipeline's goal gate and your `collect --expect` arguments. A run you can't check isn't finished when moab says so.

### 2. Write the pipeline
Follow the `moab` skill: moab's own `moab--create-pipeline`, plus the local rules.
- **Keep it outside the target repo:** in a scratch folder, or in `~/src/memory/pipelines/<project>/` if it is meant to be reused.
- **Prompts must be explicit:** what to change, how to verify it (run the tests), and "commit your changes with git".
- **Grants:** use `rw:.` when agents commit, otherwise `ro:.` plus `rw:./out`. Credentials go through `sandbox.secrets`. Never nest writable grants.
- **Pipelines never push.** Agents commit only inside the run's clone; you collect the branch and decide whether it goes to a remote. `moab-run` refuses a pipeline granting the `github` or `gitlab` route. Inside the sandbox git works without the user's global config: the clone has its own identity (`moab agent`), so prompts needn't set one.
- **Goal gate:** put `goal_gate=true` on the node that must succeed.

### 3. Validate
Run `moab pipeline validate <pipeline.dot>` and fix every error. Warnings are a judgement call; `no_goal_gate` almost always deserves a fix.

### 4. Start
```bash
moab-run start <repo> <pipeline.dot> --slug <short-name> [--base origin/main] [--param k=v] \
  --max-minutes <n> [--max-tokens <n>]
```

**Always give a budget.** moab has no spending cap, so moab-run enforces yours whenever it checks the run.
- `--max-minutes` bounds everything, including one long step.
- `--max-tokens` only bites between steps, because moab reports a step's tokens when the step ends. It catches loops and retries.
- Size them from the job: a trivial haiku step costs about 70k–300k tokens and under a minute.

**What it does:**
- **Refuses** when the daemon is down or lacks the needed key, when validation fails, when a grant reaches outside the clone, or when the pipeline asks for a git host's credentials.
- **Clones** the repo into `~/moab-runs/<repo>/<date>-<slug>/work`, on branch `moab/<slug>`.
- **Starts the run detached and sandboxed**, then prints the run id.

**Then record it:** log a `mem_log` reference with the run id, repo, slug and pipeline path, so another session can find the run.

**When the daemon isn't running,** a human has to start it, because 1Password needs a fingerprint: `launchctl kickstart -k gui/$(id -u)/org.nixos.moab-daemon`. Ask with `mem_ask`, or ask in chat if Mohib is present. Never start a daemon yourself: the guard blocks it, and the result would have no keys.

### 5. Monitor without burning tokens
- **Wait with `moab-run watch <run> --interval 30s --timeout 20m`.** It costs no tokens while it waits.
  - It enforces the budget on every check.
  - It exits 0 once the run has finished, whatever the outcome; `collect` judges it.
  - It exits 4 if the run is still going at the timeout, and leaves it running. Watch again, or stop it.
- `moab-run status <run>` is a one-off check. It also enforces the budget.
- **A run stopped for its budget** shows "stopped by moab-run: …", and `collect` fails it. Decide whether the budget was too small or the pipeline is looping.
- `moab viz` opens the dashboard for a human.
- Stop a run that has gone wrong with `moab-run stop <run>`. It stays resumable.

### 6. Collect and judge
```bash
moab-run collect <run> --expect <path> [--expect <path>]...
```

| Verdict | Exit | What to do |
|---|---|---|
| `ok` | 0 | Go on to deliver |
| `check` | 2 | moab said success but nothing was produced. Find out why before going on: usually a prompt that didn't say to commit, or a write the sandbox denied. |
| `failed` | 1 | moab's outcome wasn't success, or an expected file is missing. Diagnose it. |
| error | 3 | Read the message |

**Always review the agents' commits**, even when the verdict is `ok`. moab-run lists them; read the diff before trusting it.

### 7. Diagnose
The run's history is in `~/.moab/projects/<group>/runs/<run-id>/`:
- `events.jsonl` holds one JSON event per line, with the payload in `moabJson.json`. `agent_response_finished` carries what the agent actually said; moab's own failure line is often vaguer.
  - Example: "Authentication required" turned out to be `Invalid API key`.
- Sandbox denials show up in `console_output` events as `sandbox_denied_path`, each with a remediation.

**Common causes:**

| Symptom | Cause | Fix |
|---|---|---|
| auth failure | the daemon's key is wrong or missing | have the human fix the key, then `moab run resume <id>` |
| `sandbox_grant_integrity` | nested writable grants | one `rw:.` |
| `sandbox_working_dir` | a node without a grant covering its folder | add `ro:.` |
| denied path | the agent needs something outside its grants | add a narrow `ro:`/`rw:` inside the clone. If it needs something outside, rethink the task rather than widen the sandbox. |
| network blocked | the hostname isn't on `sandbox.net` | add it to the allowlist |
| `~/.CFUserTextEncoding` denial | harmless macOS noise | ignore it |

### 8. Fix and rerun
- **The fix is in the pipeline** (prompt, grant, topology): start a **new run** with a new slug (`<slug>-2`). moab runs a snapshot of the pipeline, so editing it doesn't change a run in progress.
- **The fix is outside the pipeline** (a key, a flaky provider): `moab run resume <run-id>` continues from the failed node.

Budget your attempts. After two or three failed runs on the same problem, stop and tell the human what you've learned.

### 9. Deliver
```bash
moab-run collect <run> --expect ... --fetch
```
- This fetches `moab/<slug>` into the source repo. It never forces and never touches the checkout.
- **Review it there:** `git -C <repo> log -p <base>..moab/<slug>`.
- **Then hand it on the usual way:** a worktree off the latest main, a PR, and the repo's own rules.
- **Treat the agents' work like an outside contribution.**
- **Never run git yourself inside a run's clone.** A sandboxed agent may have planted git settings that execute on your machine. `moab-run collect` checks for that before it touches the clone.

### 10. Clean up
`moab-run clean <run> --yes` deletes a run's folder once you're done with it. `moab-run clean --older-than 7d` lists old runs; add `--yes` to delete them.
- It never deletes a running run.
- It keeps runs whose branch you haven't fetched (`--force` overrides).

### 11. Record
- `mem_log` a **lesson** for each non-obvious thing you learned about moab, a pipeline pattern, or a failure and its fix.
- Log a **reference** for runs whose result matters: id, verdict, tokens, and where the result went (branch, PR).
- Report token use to the human. moab gives tokens, not dollars.

## Rules
- **Every run is sandboxed.** Use `moab-run`, or pass `--sandbox nono` if you must call `moab run start` yourself. The guard blocks anything else. Never use `--sandbox-allow-unsupported`.
- **Never run a pipeline you didn't write or review.** Its tool nodes run unsandboxed on this machine.
- **Never copy moab source or docs into memory:** they're confidential, and the memory repo is personal.
