---
name: fleetify
description: Use when the user says "fleetify", "become a manager", "make this a fleet", or that this session is slow, crowded or keeps getting steered off course by their messages while long work runs. Turns the current Pi session into a fleet manager in place, keeping its conversation: it plans how to hand its in-flight threads to pi-subagents children, gets the plan approved through ASKS.md, launches the children, and redefines itself with `mem agent fleetify`. Pi only; the session must be a hosted interactive agent of the shared memory.
---

# Fleetify: turn this session into a fleet manager

A session that does long work itself gets slow, and every message from Mohib steers it off course. As a **manager**,
it keeps its conversation, hands the work to pi-subagents children, and stays free to talk. On 2026-10-22 this
turned emurdha-allocations around ("it really worked and was great"). Design, agreed with Mohib on 2026-10-24: the
memory ledger, L-01M5P2DVP5RW5V6BNR59WMK2KB to L-01M5P2Z00EDJSQENZNMZ8EW9EA.

**What you'll do:** plan, have the plan approved, launch the children, run one command, end your turn. The judgment
is yours; `mem agent fleetify` does the file edits.

## 0. Check you can

- **Pi only.** In Claude Code, say it isn't supported there.
- **You must be a hosted interactive agent:** `MEM_ROLE` is `interactive`, and `MEM_AGENT` is your name.
  - Not hosted yet? Follow the `keep-session` skill first. Mohib has to `/quit` once, so do it now, while nothing is
    running: children started before a Pi restart can't report back to the new process.
  - A standing agent (`MEM_ROLE=standing`)? Stop: this skill is for interactive sessions.
- **Delegation:** Mohib asking you to fleetify authorizes the plan. Launching children needs his yes to the plan.

## 1. Read the rules you'll work under

Read `~/src/memory/agents/templates/manager-rules.md` now, in full: from this point on you follow it. Skim
`~/src/memory/agents/templates/spec.md`, the spec every child starts from.

## 2. List your threads

From this conversation, list every open thread: what it is, its state (with exact heads, run ids and paths), what's
left, and what it's waiting on. Include what you promised Mohib. Don't drop the small ones.

## 3. Route each thread

| Thread | Goes to |
|---|---|
| Waiting on someone or something (a PR review, CI, a deploy, a person) | `mem_watch`, no child (check prints `KEY=value`, match `^KEY=value`) |
| Your own command that will finish (a build, a test run) | `run_background` |
| A separable job (a fix, an investigation, a test) | a **fresh** child (`worker`, `scout`, `delegate`) with a spec from the template |
| Reviewing a diff | the built-in `reviewer`, from a different model family than the diff's **actual** author |
| The one thread that only makes sense with this whole conversation | a **forked** child (`context: "fork"`) |

- **At most one fork.** A fork carries your entire context on every turn: it is your costliest child, and on Sol the
  likeliest to cross the 272k-token price tier. Fork only code work that depends on this conversation's history (ask
  "will it change code depending on what we discussed?"), and tell it to finish or hand off early. Measured: a fork
  inheriting 230k tokens cost $0.63 for a two-turn status check.
- **Models by difficulty** (from the rules): Haiku or Sonnet for mechanical work, Sonnet or Sol for judgement.
- **Your own model after the conversion:** Sol (`openai-codex/gpt-6.1-sol`) by default. Propose another only with a
  reason.

## 4. Post the plan for approval

Post it with `mem_ask` (`qtype: yes_no`, `about: projects/<your repo>`), as an approval packet Mohib can answer
without scrolling back. One screen:

- **Threads:** one line each: the thread, where it goes, the agent and model, and the spec file it will get.
- **The fork:** which thread, and why a spec can't carry it. Or "none".
- **Your model after the restart**, and the reason if it isn't Sol.
- **Rough cost:** children's models and expected turns; the fork's size (your current context).
- **What happens on yes:** you launch the children, run `mem agent fleetify`, compact at the end of that turn, and
  restart once all children are done.
- **What won't happen:** no merges, deploys or messages to others without his separate approval.

Tell Mohib in chat with the AQ id. Keep working only on what the plan doesn't touch; the answer wakes you.

## 5. On yes: convert

Do it in one turn, in this order:

1. **Specs:** write one per fresh child in `~/src/memory/agents/<your name>/specs/`, from the template.
2. **Smoke test**, if you haven't launched children in this session yet: one small Haiku child, `async: true`, that
   returns a fixed `structuredOutput`. A foreground child runs without extensions and fails on anything memory-related. Decide on `structuredOutput`, never on the notice text. If it fails, stop and tell Mohib the
   exact error.
3. **The fork first** (it must inherit the conversation before it's compacted), then the fresh children, then the
   reviewer, all `async: true`, with `timeoutMs` above their expected run time. Then the watches.
4. **Working memory:** bring `~/src/memory/agents/<your name>/working-memory.md` up to date: the Checkpoint (the
   command adds one if it's missing), and every child's run id, model and spec under "In progress".
5. **Redefine yourself:**
   ```bash
   mem agent fleetify --approved AQ-<n>            # --model <id> if the plan said so; --dry-run to preview
   ```
   It edits your `agent.md` (the shared rules included, `compact_at`, the model, a manager section), adds a
   Checkpoint to your working memory if needed, and asks for a restart once you're idle.
6. **Fill in your `agent.md`** right away: the sections the command lists (the job, scope and authority, people,
   job-specific facts), from what you know, before you end this turn: the restart can't come mid-turn, but it can come
   a minute after it. No `<…>` placeholders left. Then commit it in `~/src/memory`, following
   that repo's `AGENTS.md` (`git add agents/<your name>/agent.md` only; pull with rebase, then push).
7. **Report** to Mohib in a few lines: what's running where, the AQ ids still open, and that the restart comes when
   the children are done. Then end your turn.

**What happens next, on its own:**
- **Compaction.** If your context is over `compact_at`, you're asked to save your working memory, then compacted.
- **The restart.** It waits until no turn, child or background job has run for a minute, then brings your manager
  prompt and model. Watches survive it. Your conversation continues.

## 6. After the restart

- Check your prompt starts with "# How every fleet manager works", and the model is what the plan said.
- Tell memory-dev (intercom, `memory-dev`) what got in your way during the conversion, with evidence. Mohib wants all
  fleet feedback sent there unprompted.
