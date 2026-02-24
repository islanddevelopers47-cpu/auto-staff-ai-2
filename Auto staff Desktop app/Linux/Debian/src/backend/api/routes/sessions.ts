import { Router } from "express";
import type Database from "better-sqlite3";
import { getSessionHistory, clearSessionHistory, listSessions, getSessionMessageCount } from "../../database/sessions.js";
import { authMiddleware } from "../../auth/middleware.js";

export function createSessionsRouter(db: Database.Database): Router {
  const router = Router();

  // List all sessions (conversation threads) for a bot, with message counts
  router.get("/bots/:botId/sessions", authMiddleware, (req, res) => {
    const sessions = listSessions(db, String(req.params.botId));
    const withCounts = sessions.map((s) => ({
      ...s,
      message_count: getSessionMessageCount(db, s.id),
    }));
    res.json({ sessions: withCounts });
  });

  router.get("/sessions/:sessionId/messages", authMiddleware, (req, res) => {
    const limit = parseInt(req.query.limit as string) || 50;
    const messages = getSessionHistory(db, String(req.params.sessionId), limit);
    res.json({ messages });
  });

  router.delete("/sessions/:sessionId/messages", authMiddleware, (req, res) => {
    clearSessionHistory(db, String(req.params.sessionId));
    res.json({ ok: true });
  });

  return router;
}
