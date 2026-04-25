import { QUICKADD_SYSTEM } from "@claude-tasks/core";
import { anthropic, HAIKU } from "./anthropic.js";

export interface ParsedQuickAdd {
  title: string;
  dueAt: string | null;
  remindAt: string | null;
  priority: 0 | 1 | 2 | 3;
  tags: string[];
  rrule: string | null;
  spamLevel: 0 | 1 | 2;
}

export async function parseQuickAdd(utterance: string, tz = process.env.TZ ?? "UTC"): Promise<ParsedQuickAdd> {
  const now = new Date().toISOString();
  const res = await anthropic.messages.create({
    model: HAIKU,
    max_tokens: 512,
    system: [
      { type: "text", text: QUICKADD_SYSTEM, cache_control: { type: "ephemeral" } },
    ] as any,
    messages: [
      {
        role: "user",
        content: `now: ${now}\ntz: ${tz}\nutterance: ${utterance}`,
      },
    ],
  });
  const text = res.content
    .filter((b): b is Anthropic.TextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
  // Strip optional code-fence
  const cleaned = text.replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
  return JSON.parse(cleaned) as ParsedQuickAdd;
}

// Avoid pulling in the full Anthropic namespace at the top level.
import type Anthropic from "@anthropic-ai/sdk";
