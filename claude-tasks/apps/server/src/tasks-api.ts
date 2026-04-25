import { ulid } from "ulid";
import { and, eq, desc, lte, gte, isNull, or } from "drizzle-orm";
import { matchesView, type ViewName, dayBounds, nextOccurrence } from "@claude-tasks/core";
import { db, schema } from "./db.js";
import type { ParsedQuickAdd } from "./quickadd.js";

export async function listView(view: ViewName) {
  const all = await db.select().from(schema.tasks).all();
  return all.filter((t) => matchesView(t, view));
}

export async function createTaskFromParsed(parsed: ParsedQuickAdd) {
  const id = ulid();
  const now = Date.now();
  const dueAt = parsed.dueAt ? Date.parse(parsed.dueAt) : null;
  const remindAt = parsed.remindAt ? Date.parse(parsed.remindAt) : dueAt;
  const insert: typeof schema.tasks.$inferInsert = {
    id,
    title: parsed.title,
    status: "todo",
    priority: parsed.priority,
    dueAt: dueAt ? new Date(dueAt) : null,
    remindAt: remindAt ? new Date(remindAt) : null,
    rrule: parsed.rrule,
    tags: parsed.tags,
    spamLevel: parsed.spamLevel,
    createdAt: new Date(now),
    updatedAt: new Date(now),
  };
  await db.insert(schema.tasks).values(insert).run();
  if (remindAt) {
    await db.insert(schema.reminders).values({
      id: ulid(),
      taskId: id,
      fireAt: new Date(remindAt),
      channel: "sms",
    }).run();
  }
  return db.select().from(schema.tasks).where(eq(schema.tasks.id, id)).get();
}

export async function appendJournal(taskId: string, body: string, source: "web" | "sms" | "cli" | "claude" | "mcp") {
  const id = ulid();
  await db.insert(schema.journalEntries).values({
    id, taskId, body, source, createdAt: new Date(),
  }).run();
  return id;
}

export async function markDone(taskId: string) {
  const task = await db.select().from(schema.tasks).where(eq(schema.tasks.id, taskId)).get();
  if (!task) return null;
  await db.update(schema.tasks)
    .set({ status: "done", ackAt: new Date(), updatedAt: new Date() })
    .where(eq(schema.tasks.id, taskId))
    .run();
  // Recurring: clone with next occurrence
  if (task.rrule) {
    const next = nextOccurrence(task.rrule, task.dueAt ?? new Date());
    if (next) {
      const newId = ulid();
      await db.insert(schema.tasks).values({
        ...task,
        id: newId,
        status: "todo",
        ackAt: null,
        dueAt: next,
        remindAt: next,
        createdAt: new Date(),
        updatedAt: new Date(),
      } as any).run();
      await db.insert(schema.reminders).values({
        id: ulid(), taskId: newId, fireAt: next, channel: "sms",
      }).run();
    }
  }
  return taskId;
}

export async function snooze(taskId: string, minutes: number) {
  const newAt = new Date(Date.now() + minutes * 60_000);
  await db.update(schema.tasks)
    .set({ remindAt: newAt, updatedAt: new Date() })
    .where(eq(schema.tasks.id, taskId)).run();
  // Reset any pending reminders
  await db.update(schema.reminders)
    .set({ fireAt: newAt, attempt: 0, status: "pending" })
    .where(and(eq(schema.reminders.taskId, taskId), eq(schema.reminders.status, "pending")))
    .run();
}

export async function ackAll() {
  await db.update(schema.tasks).set({ ackAt: new Date() }).run();
}
