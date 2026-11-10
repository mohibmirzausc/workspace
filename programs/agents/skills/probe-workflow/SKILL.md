---
name: probe-workflow
description: Use when the user asks a confidence question rather than for a task — "how confident are we?", "does it work for all of them or a subset?", "what haven't we explored?", "is there a better way?", "prove it", "probe it" — or when a claim needs evidence before anyone builds on it. Answers it by running small, mostly read-only probes on real data (in the background, or fanned out to subagents when delegation is authorized), writing an evidence file per probe, reporting verdict first, and turning each gap found into a rule tested with a planted mismatch. Interactive: the human approves probes and keeps every decision.
---

# Probe workflow: answer "how sure are we?" with evidence

For explorative work with a human in the conversation. The question is about
confidence, not a task. The answer is evidence from small probes, and each gap
the probes find becomes a rule with a test. Worked example (release admission
gate, 2026-11-09): `~/src/memory/agents/train-admission/specs/probe-workflow.md`.

## The loop

1. **Answer from what you already know, first.** Give a table per case
   (case / confidence / why), and name the unknowns. Keep three things apart:
   what we know, what we assume (say "tags never move" out loud), and what we
   don't know. If an earlier claim of yours was too strong, say "I overstated
   it" and correct it.
2. **Propose probes.** For each one, say:
   - what it would prove or disprove;
   - whether it's read-only;
   - its cost, in time and money;
   - the order to run them in ("2 first, then 1").
   On a fresh question, ask "Go?" and wait. A probe the human has given
   standing approval for can start at once, if it's read-only.
3. **Record the human's rules at once.** They often approve a subset, add a
   probe, and state lasting rules ("no org changes", "X last"). Log those
   immediately (`mem_log` kind `instruction` when the memory system is there),
   and fold any change of direction into the plan.
4. **Run probes in the background and keep talking.** Long runs go through
   `run_background`. Answer side questions and write drafts while they run;
   the completion wakes you. Name any temporary infrastructure `<human>-<topic>`
   (for example a `mohib-` pipeline), list it, and destroy it as soon as its
   result is saved.
5. **Write each result down before you report it** (see "Evidence file").
   Log anything lasting.
6. **Report the verdict first.** Then give the few facts that carry it, what
   it changes, and the next question for the human. Keep known findings apart
   from new ones, and harness problems apart from real ones. End with numbered
   questions.
7. **Turn gaps into logic, and logic into tests.** Write each gap found as a
   proposed rule. Prove the rule works by planting the mismatch, as a seeded
   change to real evidence, and showing the check catches it. Add a control
   that changes nothing and passes. Rule texts are the human's to approve.

## Probe design rules

- **Use real data, end to end.** A dry run over a real release finds what slice
  scenarios never show. In the worked example, one dry run found four gaps
  that 41 scenarios had missed.
- **Design probes that can fail.** A probe that only finds problems tells you
  nothing about what it missed. Planted mismatches measure misses ("6/6 caught,
  plus a control"). Say which kind each probe is.
- **Prefer native tools to parsing.** Ask the ecosystem's own tool, such as the
  package manager resolving the shipped artifact, before writing a parser.
- **Cross-check against an independent source.** For example, compare an image
  label with the CI system's own build log, or generated trees with the
  published POMs.
- **Check the probe itself.** Before you report, sort every odd result into
  harness or real: stale fixtures, duplicate pages from pagination, read-only
  caches, guessed versions.
- **Cheap and local first.** Try git and cached evidence before pipelines.
  Batch independent reads (codemode `Promise.allSettled`), and reuse cached
  evidence rather than rebuilding it.
- **Record exact identifiers:** commits, digests, run and build ids, pipeline
  names. A later session must be able to rerun or cite the probe.

## Evidence file

Write one per probe: `evidence/<probe>/README.md` in your working folder, or
the project's own evidence folder. Give it a fixed shape:
- **Question**
- **Method:** the commands, or a script path
- **Exact ids**
- **Verdict:** confirmed, refuted, or partial
- **Harness vs real:** which odd results came from the probe itself
- **Implied logic:** the rule it suggests, if any

## Fanning out to subagents

Fan out only when this session is authorized to delegate: the human asked, or
the agent's definition allows it. Otherwise, run the probes yourself in the
background.

- **One child per independent probe.** Use a read-only `scout` on a cheap
  model. Each child writes its evidence file in the fixed shape and returns a
  five-line verdict as structured output.
- **Tell each child that tokens cost money, not wall time.** Have it stop when
  the question is answered.
- **You keep the conversation, the approvals, the merging of verdicts, and the
  cleanup of temporary infrastructure.** Children get read-only scope, plus a
  named temporary pipeline if one is needed. One writer per worktree.
- **Optional falsifier:** a `reviewer` child that, for each claimed coverage,
  designs the planted mismatch that would break it.
- **Bring the human only what changes a decision.**

## Never

- Change production, merge, or send messages. Draft them instead.
- Edit approved rule texts without asking.
- Make a supply-chain or ownership call: "which artifacts are ours", or which
  rule applies. Bring it to the human.
- Leave temporary infrastructure behind.
