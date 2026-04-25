import express from "express";
import { ulid } from "ulid";
import { eq } from "drizzle-orm";
import { db, schema } from "./db.js";
import { listView } from "./tasks-api.js";
import { parseQuickAdd } from "./quickadd.js";
import { createTaskFromParsed, appendJournal, markDone, snooze } from "./tasks-api.js";
import { handleSmsBody } from "./sms-inbound.js";

export function buildApp() {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));

  app.get("/health", (_req, res) => res.json({ ok: true }));

  app.get("/tasks", async (req, res) => {
    const view = (req.query.view as any) ?? "today";
    res.json(await listView(view));
  });

  app.post("/tasks/quickadd", async (req, res) => {
    const utterance = String(req.body.utterance ?? "").trim();
    if (!utterance) return res.status(400).json({ error: "utterance required" });
    const parsed = await parseQuickAdd(utterance);
    const task = await createTaskFromParsed(parsed);
    res.json({ parsed, task });
  });

  app.post("/tasks/:id/note", async (req, res) => {
    const body = String(req.body.body ?? "").trim();
    if (!body) return res.status(400).json({ error: "body required" });
    const id = await appendJournal(req.params.id, body, "web");
    res.json({ id });
  });

  app.post("/tasks/:id/done", async (req, res) => {
    await markDone(req.params.id);
    res.json({ ok: true });
  });

  app.post("/tasks/:id/snooze", async (req, res) => {
    const minutes = Number(req.body.minutes);
    if (!Number.isFinite(minutes)) return res.status(400).json({ error: "minutes required" });
    await snooze(req.params.id, minutes);
    res.json({ ok: true });
  });

  app.post("/tasks/:id/claude", async (req, res) => {
    const instruction = String(req.body.instruction ?? "").trim();
    if (!instruction) return res.status(400).json({ error: "instruction required" });
    const id = ulid();
    await db
      .insert(schema.claudeTodos)
      .values({ id, taskId: req.params.id, instruction, createdAt: new Date() })
      .run();
    res.json({ id });
  });

  app.get("/tasks/:id/journal", async (req, res) => {
    const rows = await db
      .select()
      .from(schema.journalEntries)
      .where(eq(schema.journalEntries.taskId, req.params.id))
      .all();
    res.json(rows);
  });

  // Twilio inbound SMS webhook
  app.post("/sms/inbound", async (req, res) => {
    const from = String(req.body.From ?? "");
    const body = String(req.body.Body ?? "");
    const owner = process.env.OWNER_PHONE;
    if (owner && from !== owner) {
      console.warn(`[sms-inbound] rejecting ${from}`);
      return res.status(403).end();
    }
    const reply = await handleSmsBody(body);
    res.type("text/xml").send(
      `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${escapeXml(reply)}</Message></Response>`,
    );
  });

  return app;
}

function escapeXml(s: string): string {
  return s.replace(/[<>&'"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&apos;", '"': "&quot;" })[c]!);
}
