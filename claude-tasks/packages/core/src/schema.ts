import { sqliteTable, text, integer, index } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";

export const tasks = sqliteTable(
  "tasks",
  {
    id: text("id").primaryKey(),
    title: text("title").notNull(),
    status: text("status", {
      enum: ["inbox", "todo", "doing", "done", "cancelled"],
    })
      .notNull()
      .default("inbox"),
    priority: integer("priority").notNull().default(0),
    dueAt: integer("due_at", { mode: "timestamp_ms" }),
    remindAt: integer("remind_at", { mode: "timestamp_ms" }),
    rrule: text("rrule"),
    projectId: text("project_id"),
    parentId: text("parent_id"),
    tags: text("tags", { mode: "json" }).$type<string[]>().default([]),
    notes: text("notes").notNull().default(""),
    spamLevel: integer("spam_level").notNull().default(0),
    ackAt: integer("ack_at", { mode: "timestamp_ms" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
    updatedAt: integer("updated_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    statusIdx: index("tasks_status_idx").on(t.status),
    dueIdx: index("tasks_due_idx").on(t.dueAt),
    remindIdx: index("tasks_remind_idx").on(t.remindAt),
  }),
);

export const journalEntries = sqliteTable(
  "journal_entries",
  {
    id: text("id").primaryKey(),
    taskId: text("task_id")
      .notNull()
      .references(() => tasks.id, { onDelete: "cascade" }),
    body: text("body").notNull(),
    source: text("source", {
      enum: ["web", "sms", "cli", "claude", "mcp"],
    }).notNull(),
    createdAt: integer("created_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    taskIdx: index("journal_task_idx").on(t.taskId),
  }),
);

export const claudeTodos = sqliteTable(
  "claude_todos",
  {
    id: text("id").primaryKey(),
    taskId: text("task_id")
      .notNull()
      .references(() => tasks.id, { onDelete: "cascade" }),
    instruction: text("instruction").notNull(),
    status: text("status", {
      enum: ["queued", "running", "blocked", "done", "failed"],
    })
      .notNull()
      .default("queued"),
    result: text("result"),
    error: text("error"),
    startedAt: integer("started_at", { mode: "timestamp_ms" }),
    finishedAt: integer("finished_at", { mode: "timestamp_ms" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    statusIdx: index("claude_todos_status_idx").on(t.status),
  }),
);

export const reminders = sqliteTable(
  "reminders",
  {
    id: text("id").primaryKey(),
    taskId: text("task_id")
      .notNull()
      .references(() => tasks.id, { onDelete: "cascade" }),
    fireAt: integer("fire_at", { mode: "timestamp_ms" }).notNull(),
    channel: text("channel", { enum: ["sms", "push", "telegram"] })
      .notNull()
      .default("sms"),
    attempt: integer("attempt").notNull().default(0),
    status: text("status", {
      enum: ["pending", "sent", "acked", "failed"],
    })
      .notNull()
      .default("pending"),
  },
  (t) => ({
    fireIdx: index("reminders_fire_idx").on(t.fireAt, t.status),
  }),
);

export type Task = typeof tasks.$inferSelect;
export type NewTask = typeof tasks.$inferInsert;
export type JournalEntry = typeof journalEntries.$inferSelect;
export type ClaudeTodo = typeof claudeTodos.$inferSelect;
export type Reminder = typeof reminders.$inferSelect;
