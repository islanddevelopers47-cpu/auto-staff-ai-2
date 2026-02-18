import { Router } from "express";
import { executeCommand, getSystemInfo, whichBinary } from "../../local/shell-executor.js";
import * as localFs from "../../local/file-system.js";
import { processManager } from "../../local/process-manager.js";
import { checkBinary, checkBinaries, installBinary, hasWinget, hasChocolatey } from "../../local/dependency-checker.js";
import { authMiddleware } from "../../auth/middleware.js";
import { createLogger } from "../../utils/logger.js";

const log = createLogger("api-local");

export function createLocalRouter(): Router {
  const router = Router();

  // All local routes require auth
  router.use("/local", authMiddleware);

  // --- Shell ---

  // Execute a command
  router.post("/local/shell/exec", async (req, res) => {
    const { command, cwd, timeout, env } = req.body;
    if (!command || typeof command !== "string") {
      res.status(400).json({ error: "command is required" });
      return;
    }
    try {
      const result = await executeCommand(command, {
        cwd: cwd?.replace(/^~/, process.env.USERPROFILE || process.env.HOME || ""),
        timeout,
        env,
      });
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // System info
  router.get("/local/system-info", (_req, res) => {
    res.json(getSystemInfo());
  });

  // Which binary
  router.get("/local/which/:name", (req, res) => {
    const binPath = whichBinary(req.params.name);
    res.json({ name: req.params.name, found: !!binPath, path: binPath });
  });

  // --- File System ---

  // List directory
  router.get("/local/fs/list", (req, res) => {
    const dirPath = ((req.query.path as string) || "~").replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
    const hidden = req.query.hidden === "true";
    try {
      const files = localFs.listDirectory(dirPath, hidden);
      res.json({ path: dirPath, files });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Read file
  router.get("/local/fs/read", (req, res) => {
    const filePath = ((req.query.path as string) || "").replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
    if (!filePath) { res.status(400).json({ error: "path is required" }); return; }
    try {
      const file = localFs.readFile(filePath);
      res.json(file);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Write file
  router.post("/local/fs/write", (req, res) => {
    const { path: filePath, content } = req.body;
    if (!filePath) { res.status(400).json({ error: "path is required" }); return; }
    try {
      const resolved = filePath.replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
      const result = localFs.writeFile(resolved, content || "");
      res.json(result);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Create directory
  router.post("/local/fs/mkdir", (req, res) => {
    const { path: dirPath } = req.body;
    if (!dirPath) { res.status(400).json({ error: "path is required" }); return; }
    try {
      const resolved = dirPath.replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
      const result = localFs.createDirectory(resolved);
      res.json(result);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Delete
  router.delete("/local/fs/delete", (req, res) => {
    const filePath = ((req.query.path as string) || "").replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
    const recursive = req.query.recursive === "true";
    if (!filePath) { res.status(400).json({ error: "path is required" }); return; }
    try {
      const result = localFs.deleteItem(filePath, recursive);
      res.json(result);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Move
  router.post("/local/fs/move", (req, res) => {
    const { from, to } = req.body;
    if (!from || !to) { res.status(400).json({ error: "from and to are required" }); return; }
    try {
      const result = localFs.moveItem(
        from.replace(/^~/, process.env.USERPROFILE || process.env.HOME || ""),
        to.replace(/^~/, process.env.USERPROFILE || process.env.HOME || "")
      );
      res.json(result);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Find files
  router.get("/local/fs/find", (req, res) => {
    const dirPath = ((req.query.path as string) || "~").replace(/^~/, process.env.USERPROFILE || process.env.HOME || "");
    const pattern = req.query.pattern as string;
    if (!pattern) { res.status(400).json({ error: "pattern is required" }); return; }
    try {
      const results = localFs.findFiles(dirPath, pattern);
      res.json({ path: dirPath, pattern, results });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // --- Processes ---

  // Start process
  router.post("/local/proc/start", (req, res) => {
    const { command, cwd } = req.body;
    if (!command) { res.status(400).json({ error: "command is required" }); return; }
    try {
      const proc = processManager.start(command, {
        cwd: cwd?.replace(/^~/, process.env.USERPROFILE || process.env.HOME || ""),
      });
      res.json(proc);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Stop process
  router.post("/local/proc/:id/stop", (req, res) => {
    try {
      const stopped = processManager.stop(req.params.id);
      res.json({ id: req.params.id, stopped });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Send input
  router.post("/local/proc/:id/input", (req, res) => {
    const { input } = req.body;
    if (!input) { res.status(400).json({ error: "input is required" }); return; }
    try {
      const sent = processManager.sendInput(req.params.id, input + "\n");
      res.json({ id: req.params.id, sent });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  // Get process status
  router.get("/local/proc/:id", (req, res) => {
    const proc = processManager.getProcess(req.params.id);
    if (!proc) { res.status(404).json({ error: "Process not found" }); return; }
    const output = processManager.getOutput(req.params.id, parseInt(req.query.tail as string || "50", 10));
    res.json({ ...proc, recentOutput: output });
  });

  // List all processes
  router.get("/local/proc", (_req, res) => {
    res.json(processManager.listProcesses());
  });

  // Remove process
  router.delete("/local/proc/:id", (req, res) => {
    const removed = processManager.remove(req.params.id);
    res.json({ id: req.params.id, removed });
  });

  // --- Dependencies ---

  // Check binary
  router.get("/local/deps/check/:name", (req, res) => {
    res.json(checkBinary(req.params.name));
  });

  // Check multiple binaries
  router.post("/local/deps/check", (req, res) => {
    const { names } = req.body;
    if (!Array.isArray(names)) { res.status(400).json({ error: "names array is required" }); return; }
    res.json(checkBinaries(names));
  });

  // Install binary
  router.post("/local/deps/install", async (req, res) => {
    const { name } = req.body;
    if (!name) { res.status(400).json({ error: "name is required" }); return; }
    try {
      const result = await installBinary(name);
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Package manager status (winget / chocolatey)
  router.get("/local/deps/homebrew", (_req, res) => {
    res.json({ installed: hasWinget(), winget: hasWinget(), chocolatey: hasChocolatey() });
  });

  return router;
}
