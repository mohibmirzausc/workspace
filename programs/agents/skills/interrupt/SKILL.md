---
name: interrupt
description: Use when an unplanned interrupt task pulls you off the current story — the user says "/interrupt", "I got interrupted", "log this interrupt", "something came up", or describes an urgent issue they now have to handle. Files a Shortcut interrupt story in Release Engineering (Started, owned by the invoking user, tagged `interrupts`) and posts a heads-up to #platform-release-engineering.
---

# Interrupt

File an interrupt: capture the sidetrack task as a Shortcut story and notify the release-engineering team on Slack that the user is on it.

## What you're given

Whatever context is in the conversation about the interrupting task — a failing pipeline, a broken build, an incident, a request, an alert. If the context is thin (you don't know *what* the interrupt is or *why* it matters), ask one quick clarifying question before proceeding. Otherwise summarize from what's already there.

## Fixed facts (this workspace)

These IDs are stable — use them directly, don't re-look-them-up unless a call fails.
(Team, workflow and "Started" state verified against the Shortcut API on 2026-07-30.)

| Thing | Value |
|---|---|
| Shortcut team | Release Engineering — `6940a30c-5eba-4d83-9e99-6a14eec7df14` |
| Workflow | Shared Workflow `500000566` |
| "Started" state | `500000569` |
| Label | `interrupts` |
| Slack channel | `#platform-release-engineering` → `C0A3RTPJ8GJ` |

The **owner is the invoking user**, looked up at runtime (see step 3) — do not hard-code it, since this skill is shared across the team.

The Shortcut and Slack tools are **deferred** — load their schemas first:
`ToolSearch("select:mcp__shortcut__users-get-current,mcp__shortcut__stories-create,mcp__shortcut__stories-update,mcp__plugin_slack_slack__slack_send_message")`

## Steps

### 1. Draft the story and the Slack message

Call `mcp__shortcut__users-get-current` first — you need the invoking user's `name` for
the Slack draft and their `id` as the story owner in step 3. One call, reused twice.

From the conversation context, write:

- **Story name** — one concise line naming the problem (e.g. "Concourse merge-queue wedged after GAR :latest restale").
- **Story description** — a short summary: what the issue is, impact/why it's an interrupt, and any relevant links or story/PR IDs already in context. Note it pulled work off the current story if that's known.
- **Slack message** — 2–4 sentences for the team: what's happening, the impact, and that the invoking user is picking it up now. Use their name from the `users-get-current` call above — do **not** hard-code a name, since this skill is shared across the team. Plain, calm, informative. Include the Shortcut story link once created. Address the channel, no @here unless the user says it's urgent enough to warrant it.

### 2. Confirm before writing anything outward

Show the user the drafted story (name + description) and the drafted Slack message. Posting to a team channel is outward-facing — get a quick go-ahead (or edits) before sending. If the user already said "just do it" / "no need to confirm," skip straight to step 3.

### 3. Create the Shortcut story

Use the `id` from the `users-get-current` call in step 1 as the owner.

`stories-create` doesn't take a workflow state or labels, so it's two calls:

1. `mcp__shortcut__stories-create` with:
   - `name`: the story name
   - `description`: the description
   - `type`: `chore` (interrupts are usually operational; use `bug` if it's clearly a defect)
   - `team`: `6940a30c-5eba-4d83-9e99-6a14eec7df14`
   - `owner`: the `id` from `users-get-current`
2. `mcp__shortcut__stories-update` with the returned `storyPublicId` and:
   - `workflow_state_id`: `500000569`  (Started)
   - `labels`: `[{ "name": "interrupts" }]`

Grab the story's `app_url` from the create response for the Slack message.

### 4. Post to Slack

`mcp__plugin_slack_slack__slack_send_message` with `channel_id: "C0A3RTPJ8GJ"` and the confirmed message, including the story link. Return the message permalink to the user.

## Report back

Tell the user: the story ID + link, that it's in Started/owned by them/tagged `interrupts`, and the Slack permalink.

## Notes

- The self-hosted Shortcut MCP server emits a deprecation warning — ignore it, the calls still work.
- If `team`-based create is rejected, fall back to `workflow: 500000566` on create, then set the team via `stories-update` (`team_id`).
