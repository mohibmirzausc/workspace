#!/usr/bin/env node
// Thin client that talks to the running server. Keeps zero schema duplication.

const BASE = process.env.TK_SERVER ?? "http://localhost:4000";

async function jpost(path: string, body: any) {
  const r = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}
async function jget(path: string) {
  const r = await fetch(`${BASE}${path}`);
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}

const [, , cmd, ...rest] = process.argv;

switch (cmd) {
  case "add": {
    const utterance = rest.join(" ");
    const out = await jpost("/tasks/quickadd", { utterance });
    console.log(out);
    break;
  }
  case "today":
  case "inbox":
  case "upcoming":
  case "doing":
  case "all": {
    const tasks = await jget(`/tasks?view=${cmd}`);
    for (const t of tasks as any[]) {
      const due = t.dueAt ? new Date(t.dueAt).toLocaleString() : "";
      const p = t.priority ? `!p${t.priority}` : "";
      const spam = t.spamLevel >= 2 ? "🚨" : "";
      console.log(`${t.id.slice(-6)}  ${spam}${p}  ${t.title}  ${due}`);
    }
    break;
  }
  case "done":
    await jpost(`/tasks/${rest[0]}/done`, {});
    break;
  case "snooze":
    await jpost(`/tasks/${rest[0]}/snooze`, { minutes: Number(rest[1]) });
    break;
  case "note":
    await jpost(`/tasks/${rest[0]}/note`, { body: rest.slice(1).join(" ") });
    break;
  case "claude":
    await jpost(`/tasks/${rest[0]}/claude`, { instruction: rest.slice(1).join(" ") });
    break;
  default:
    console.log(`tk - claude-tasks CLI

Usage:
  tk add <natural language>          quick-add a task (Claude parses it)
  tk today | inbox | upcoming        list a view
  tk done <id>                       mark done (rolls recurrence)
  tk snooze <id> <minutes>           push reminder
  tk note <id> <text>                append a journal entry
  tk claude <id> <instruction>       queue a Claude todo on the task

Server: ${BASE}`);
}
