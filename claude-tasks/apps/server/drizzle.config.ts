import type { Config } from "drizzle-kit";

export default {
  schema: "../../packages/core/src/schema.ts",
  out: "./drizzle",
  dialect: "sqlite",
  dbCredentials: { url: process.env.DB_PATH ?? "./tasks.db" },
} satisfies Config;
