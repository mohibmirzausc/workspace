import { desc, or, eq, ne } from "drizzle-orm";
import { SMS_PARSE_SYSTEM } from "@claude-tasks/core";
import { anthropic, HAIKU } from "./anthropic.js";
import { db, schema } from "./db.js";
import { appendJournal, markDone, snooze, ackAll } from "./tasks-api.js";

interface SmsCommand {
  action: "done" | "snooze" | "note" | "ack" | "start" | "cancel" | "list" | "unknown";
  taskId: string | null;
  snoozeMinutes: number | null;
  noteBody: string | null;
  reply: string;
}

export async function handleSmsBody(body: string): Promise<string> {
  const recent = await db
    .select({ id: schema.tasks.id, title: schema.tasks.title, status: schema.tasks.status })
    .from(schema.tasks)
    .where(or(ne(schema.tasks.status, "done"), ne(schema.tasks.status, "cancelled")))
    .orderBy(desc(schema.tasks.updatedAt))
    .limit(20)
    .all();

  const res = await anthropic.messages.create({
    model: HAIKU,
    max_tokens: 256,
    system: [
      { type: "text", text: SMS_PARSE_SYSTEM, cache_control: { type: "ephemeral" } },
    ] as any,
    messages: [
      { role: "user", content: `recent tasks:\n${JSON.stringify(recent)}\n\nuser sms: ${body}` },
    ],
  });
  const text = (res.content.find((b) => b.type === "text") as any)?.text ?? "{}";
  const cleaned = text.replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
  const cmd: SmsCommand = JSON.parse(cleaned);

  switch (cmd.action) {
    case "done":
      if (cmd.taskId) await markDone(cmd.taskId);
      break;
    case "snooze":
      if (cmd.taskId && cmd.snoozeMinutes) await snooze(cmd.taskId, cmd.snoozeMinutes);
      break;
    case "note":
      if (cmd.taskId && cmd.noteBody) await appendJournal(cmd.taskId, cmd.noteBody, "sms");
      break;
    case "ack":
      await ackAll();
      break;
    case "list":
      // reply already prepared by Claude — fine.
      break;
  }
  return cmd.reply;
}
