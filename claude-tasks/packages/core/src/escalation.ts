// Reminder escalation policies.
//
// Each entry is the delay (ms) until the *next* attempt, indexed by current attempt count.
// Index 0 = wait this long after the original fireAt before attempt #1 (always 0 — fire immediately).
// Subsequent indices = wait this long between attempts.

export const NORMAL_ESCALATION_MS = [0, 5 * 60_000, 10 * 60_000, 20 * 60_000, 30 * 60_000];

// Spam mode: keeps texting until you reply.
export const SPAM_ESCALATION_MS = [
  0,
  60_000,
  60_000,
  60_000,
  90_000,
  120_000,
  180_000,
  300_000,
  600_000,
  900_000,
];

export function nextDelayMs(spamLevel: number, attempt: number): number | null {
  const schedule = spamLevel >= 2 ? SPAM_ESCALATION_MS : NORMAL_ESCALATION_MS;
  return attempt + 1 < schedule.length ? schedule[attempt + 1] : null;
}
