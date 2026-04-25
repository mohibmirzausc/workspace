import { and, eq, lte, isNotNull } from "drizzle-orm";
import { nextDelayMs } from "@claude-tasks/core";
import { db, schema } from "./db.js";
import { sendSms } from "./sms.js";

export async function tick(now = Date.now()): Promise<void> {
  const due = await db
    .select()
    .from(schema.reminders)
    .where(and(eq(schema.reminders.status, "pending"), lte(schema.reminders.fireAt, now)))
    .all();

  for (const r of due) {
    const task = await db
      .select()
      .from(schema.tasks)
      .where(eq(schema.tasks.id, r.taskId))
      .get();
    if (!task) {
      await db.update(schema.reminders).set({ status: "failed" }).where(eq(schema.reminders.id, r.id));
      continue;
    }

    // Already acked since this reminder was scheduled — silence it.
    if (task.ackAt && task.ackAt > r.fireAt) {
      await db.update(schema.reminders).set({ status: "acked" }).where(eq(schema.reminders.id, r.id));
      continue;
    }

    const banner = task.spamLevel >= 2 ? "🚨 SPAM REMINDER" : "⏰ Reminder";
    const lines = [
      `${banner}: ${task.title}`,
      task.dueAt ? `due ${new Date(task.dueAt).toLocaleString()}` : null,
      `reply "done", "snooze 1h", "note: …" — id ${task.id.slice(-6)}`,
    ].filter(Boolean) as string[];
    await sendSms(lines.join("\n"));

    const delay = nextDelayMs(task.spamLevel, r.attempt);
    if (delay == null) {
      await db.update(schema.reminders).set({ status: "sent" }).where(eq(schema.reminders.id, r.id));
    } else {
      await db
        .update(schema.reminders)
        .set({ fireAt: now + delay, attempt: r.attempt + 1 })
        .where(eq(schema.reminders.id, r.id));
    }
  }
}

export function startReminderLoop(intervalMs = 30_000): NodeJS.Timeout {
  const run = () => tick().catch((e) => console.error("[reminders] tick failed:", e));
  run();
  return setInterval(run, intervalMs);
}

export { isNotNull };
