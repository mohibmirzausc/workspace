import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import * as schema from "@claude-tasks/core/schema";

const path = process.env.DB_PATH ?? "./tasks.db";
const sqlite = new Database(path);
sqlite.pragma("journal_mode = WAL");
sqlite.pragma("foreign_keys = ON");

export const db = drizzle(sqlite, { schema });
export { schema };

// FTS5 virtual table over notes + journal bodies. Created idempotently.
sqlite.exec(`
  CREATE VIRTUAL TABLE IF NOT EXISTS task_search USING fts5(
    task_id UNINDEXED, kind UNINDEXED, body, tokenize='porter'
  );
`);
