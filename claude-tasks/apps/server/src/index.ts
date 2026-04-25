import "dotenv/config";
import { buildApp } from "./http.js";
import { startReminderLoop } from "./reminders.js";
import { startOrchestratorLoop } from "./orchestrator.js";

const port = Number(process.env.PORT ?? 4000);

const app = buildApp();
app.listen(port, () => {
  console.log(`[claude-tasks] http on :${port}`);
});

startReminderLoop();
startOrchestratorLoop();
