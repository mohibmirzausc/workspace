// Appends the reply-style reminder (~/.pi/agent/reply-style.md) to every prompt typed in a Pi window, so it sits
// next to the question instead of thousands of tokens away in AGENTS.md, where long sessions forget it.
// Only typed prompts in a session with a UI: not intercom, child or background notices, `pi -p`, or subagent
// children (no UI). Not commands (`/…`) or shell lines (`!…`). Off with PI_REPLY_STYLE=0; PI_REPLY_STYLE_FILE
// points it at another file (tests).
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const FILE = process.env.PI_REPLY_STYLE_FILE || join(homedir(), ".pi", "agent", "reply-style.md");

export default function (pi: any) {
  if (process.env.PI_REPLY_STYLE === "0") return;
  pi.on("input", async (event: any, ctx: any) => {
    const text: string = event.text ?? "";
    if (event.source !== "interactive" || !ctx.hasUI) return { action: "continue" };
    if (!text.trim() || text.startsWith("/") || text.startsWith("!")) return { action: "continue" };
    let style = "";
    try {
      style = readFileSync(FILE, "utf8").trim();
    } catch {
      return { action: "continue" };
    }
    if (!style || text.includes(style.split("\n")[0])) return { action: "continue" };
    return { action: "transform", text: `${text}\n\n${style}`, images: event.images };
  });
}
