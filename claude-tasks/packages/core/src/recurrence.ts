import { RRule, rrulestr } from "rrule";

export function nextOccurrence(rrule: string, after: Date = new Date()): Date | null {
  const rule = rrulestr(rrule);
  return rule.after(after, false) ?? null;
}

export function isValidRRule(rrule: string): boolean {
  try {
    rrulestr(rrule);
    return true;
  } catch {
    return false;
  }
}

export { RRule };
