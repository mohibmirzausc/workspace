// MCP server exposing the task DB as tools, so Claude Code (or any MCP client)
// can read/mutate tasks from anywhere on your machine.
//
// Run with: tsx src/mcp.ts   (or via the Claude Code MCP config, see README.)
//
// Wire into Claude Code with ~/.claude/mcp.json:
//   { "mcpServers": { "claude-tasks": {
//       "command": "node", "args": ["--import","tsx","/abs/path/apps/server/src/mcp.ts"]
//     } } }

import "dotenv/config";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { ulid } from "ulid";
import { eq, desc } from "drizzle-orm";
import { db, schema } from "./db.js";
import { listView } from "./tasks-api.js";
import { parseQuickAdd } from "./quickadd.js";
import { createTaskFromParsed, appendJournal, markDone, snooze } from "./tasks-api.js";

const server = new Server(
  { name: "claude-tasks", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "tasks_list",
      description: "List tasks for a view (today | inbox | upcoming | doing | done | all).",
      inputSchema: {
        type: "object",
        properties: { view: { type: "string", enum: ["today", "inbox", "upcoming", "doing", "done", "all"] } },
        required: ["view"],
      },
    },
    {
      name: "tasks_quickadd",
      description: "Create a task from a natural-language utterance like 'tomorrow 3pm call mom !p2'.",
      inputSchema: {
        type: "object",
        properties: { utterance: { type: "string" } },
        required: ["utterance"],
      },
    },
    {
      name: "tasks_append_note",
      description: "Append a journal entry to a task.",
      inputSchema: {
        type: "object",
        properties: { task_id: { type: "string" }, body: { type: "string" } },
        required: ["task_id", "body"],
      },
    },
    {
      name: "tasks_done",
      description: "Mark a task done (and roll its recurrence if any).",
      inputSchema: {
        type: "object",
        properties: { task_id: { type: "string" } },
        required: ["task_id"],
      },
    },
    {
      name: "tasks_snooze",
      description: "Snooze a task by N minutes.",
      inputSchema: {
        type: "object",
        properties: { task_id: { type: "string" }, minutes: { type: "number" } },
        required: ["task_id", "minutes"],
      },
    },
    {
      name: "tasks_add_claude_todo",
      description: "Queue a Claude instruction tied to a task. The orchestrator runs it and appends the result to the task journal.",
      inputSchema: {
        type: "object",
        properties: { task_id: { type: "string" }, instruction: { type: "string" } },
        required: ["task_id", "instruction"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  switch (name) {
    case "tasks_list": {
      const tasks = await listView(args!.view as any);
      return { content: [{ type: "text", text: JSON.stringify(tasks, null, 2) }] };
    }
    case "tasks_quickadd": {
      const parsed = await parseQuickAdd(String(args!.utterance));
      const task = await createTaskFromParsed(parsed);
      return { content: [{ type: "text", text: JSON.stringify({ parsed, task }, null, 2) }] };
    }
    case "tasks_append_note": {
      const id = await appendJournal(String(args!.task_id), String(args!.body), "mcp");
      return { content: [{ type: "text", text: `appended ${id}` }] };
    }
    case "tasks_done": {
      await markDone(String(args!.task_id));
      return { content: [{ type: "text", text: "ok" }] };
    }
    case "tasks_snooze": {
      await snooze(String(args!.task_id), Number(args!.minutes));
      return { content: [{ type: "text", text: "ok" }] };
    }
    case "tasks_add_claude_todo": {
      const id = ulid();
      await db.insert(schema.claudeTodos).values({
        id,
        taskId: String(args!.task_id),
        instruction: String(args!.instruction),
        createdAt: new Date(),
      }).run();
      return { content: [{ type: "text", text: `queued ${id}` }] };
    }
    default:
      throw new Error(`unknown tool ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
