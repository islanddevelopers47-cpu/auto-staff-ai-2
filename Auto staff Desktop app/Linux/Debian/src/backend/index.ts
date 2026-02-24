// Desktop app: backend startup is handled by src/main/electron.ts
// This file is intentionally inert — it only re-exports modules for convenience.
export { loadEnv } from "./config/env.js";
export { createLogger } from "./utils/logger.js";
export { startServer } from "./server.js";
export { initDatabase } from "./database/db.js";
export { ensureAdminUser } from "./database/users.js";
export { BotManager } from "./telegram/bot-manager.js";
export { AgentRegistry } from "./agents/agent-registry.js";
export { initFirebase } from "./auth/firebase.js";
export { setAuthDb } from "./auth/middleware.js";
