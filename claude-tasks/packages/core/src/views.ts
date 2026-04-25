// Pure view-filter predicates. The server applies these as SQL where-clauses;
// the web client reuses them for in-memory filtering of cached lists.

import type { Task } from "./schema";

export type ViewName = "today" | "inbox" | "upcoming" | "doing" | "done" | "all";

export function dayBounds(d = new Date()): { start: number; end: number } {
  const start = new Date(d);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start: start.getTime(), end: end.getTime() };
}

export function matchesView(task: Task, view: ViewName, now = new Date()): boolean {
  if (task.status === "cancelled") return false;
  switch (view) {
    case "all":
      return true;
    case "inbox":
      return task.status === "inbox";
    case "doing":
      return task.status === "doing";
    case "done":
      return task.status === "done";
    case "today": {
      if (task.status === "done") return false;
      const { end } = dayBounds(now);
      const dueOrRemind = task.dueAt ?? task.remindAt;
      if (dueOrRemind && dueOrRemind < end) return true;
      if (task.status === "doing") return true;
      return false;
    }
    case "upcoming": {
      if (task.status === "done") return false;
      const { end } = dayBounds(now);
      const sevenDays = end + 7 * 24 * 60 * 60_000;
      const dueOrRemind = task.dueAt ?? task.remindAt;
      return dueOrRemind != null && dueOrRemind >= end && dueOrRemind < sevenDays;
    }
  }
}

// Eisenhower matrix quadrant: priority high (>=2) × due-soon (within 24h)
export function matrixQuadrant(task: Task, now = new Date()): "do" | "schedule" | "delegate" | "drop" {
  const dueSoon = task.dueAt != null && task.dueAt - now.getTime() < 24 * 60 * 60_000;
  const high = task.priority >= 2;
  if (high && dueSoon) return "do";
  if (high && !dueSoon) return "schedule";
  if (!high && dueSoon) return "delegate";
  return "drop";
}
