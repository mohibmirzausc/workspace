import { eq, and } from "drizzle-orm";
import { ORCHESTRATOR_SYSTEM } from "@claude-tasks/core";
import { anthropic, OPUS } from "./anthropic.js";
import { db, schema } from "./db.js";
import { appendJournal } from "./tasks-api.js";

const TOOLS = [
  {
    name: "append_journal",
    description: "Append a markdown entry to this task's journal.",
    input_schema: {
      type: "object",
      properties: { body: { type: "string" } },
      required: ["body"],
    },
  },
  {
    name: "update_task",
    description: "Patch fields on this task. Only title/notes/status/priority/tags allowed.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string" },
        notes: { type: "string" },
        status: { type: "string", enum: ["inbox", "todo", "doing", "done", "cancelled"] },
        priority: { type: "number" },
        tags: { type: "array", items: { type: "string" } },
      },
    },
  },
] as const;

async function runTool(taskId: string, name: string, input: any): Promise<string> {
  if (name === "append_journal") {
    await appendJournal(taskId, input.body, "claude");
    return "ok";
  }
  if (name === "update_task") {
    const patch: Record<string, any> = { updatedAt: new Date() };
    for (const k of ["title", "notes", "status", "priority", "tags"]) {
      if (k in input) patch[k] = input[k];
    }
    await db.update(schema.tasks).set(patch).where(eq(schema.tasks.id, taskId)).run();
    return "ok";
  }
  return `unknown tool ${name}`;
}

export async function runTodo(todoId: string): Promise<void> {
  const todo = await db
    .select()
    .from(schema.claudeTodos)
    .where(eq(schema.claudeTodos.id, todoId))
    .get();
  if (!todo) return;

  const task = await db
    .select()
    .from(schema.tasks)
    .where(eq(schema.tasks.id, todo.taskId))
    .get();
  if (!task) return;

  const journal = await db
    .select()
    .from(schema.journalEntries)
    .where(eq(schema.journalEntries.taskId, task.id))
    .all();

  await db
    .update(schema.claudeTodos)
    .set({ status: "running", startedAt: new Date() })
    .where(eq(schema.claudeTodos.id, todoId))
    .run();

  const messages: any[] = [
    {
      role: "user",
      content: `# TASK\n${task.title}\n\n## NOTES\n${task.notes}\n\n## JOURNAL\n${journal
        .map((j) => `- [${new Date(j.createdAt).toISOString()}] (${j.source}) ${j.body}`)
        .join("\n")}\n\n## INSTRUCTION\n${todo.instruction}`,
    },
  ];

  // Up to 6 tool-use rounds.
  let finalText = "";
  for (let i = 0; i < 6; i++) {
    const res = await anthropic.messages.create({
      model: OPUS,
      max_tokens: 4096,
      system: ORCHESTRATOR_SYSTEM,
      tools: TOOLS as any,
      messages,
    });
    messages.push({ role: "assistant", content: res.content });

    const toolUses = res.content.filter((b: any) => b.type === "tool_use");
    if (toolUses.length === 0 || res.stop_reason === "end_turn") {
      finalText = res.content
        .filter((b: any) => b.type === "text")
        .map((b: any) => b.text)
        .join("\n");
      break;
    }

    const toolResults = [];
    for (const tu of toolUses as any[]) {
      const out = await runTool(task.id, tu.name, tu.input);
      toolResults.push({ type: "tool_result", tool_use_id: tu.id, content: out });
    }
    messages.push({ role: "user", content: toolResults });
  }

  await db
    .update(schema.claudeTodos)
    .set({ status: "done", finishedAt: new Date(), result: finalText })
    .where(eq(schema.claudeTodos.id, todoId))
    .run();
  if (finalText) await appendJournal(task.id, `**Claude:**\n${finalText}`, "claude");
}

export async function drainTodos(): Promise<void> {
  const queued = await db
    .select()
    .from(schema.claudeTodos)
    .where(eq(schema.claudeTodos.status, "queued"))
    .all();
  for (const t of queued) {
    try {
      await runTodo(t.id);
    } catch (e: any) {
      await db
        .update(schema.claudeTodos)
        .set({ status: "failed", error: String(e?.message ?? e), finishedAt: new Date() })
        .where(eq(schema.claudeTodos.id, t.id))
        .run();
    }
  }
}

export function startOrchestratorLoop(intervalMs = 5_000): NodeJS.Timeout {
  const run = () => drainTodos().catch((e) => console.error("[orchestrator] drain failed:", e));
  return setInterval(run, intervalMs);
}
