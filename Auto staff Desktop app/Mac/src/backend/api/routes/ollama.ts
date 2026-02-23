import { Router } from "express";
import { exec, spawn } from "node:child_process";
import { promisify } from "node:util";
import * as os from "node:os";
import { authMiddleware } from "../../auth/middleware.js";
import { createLogger } from "../../utils/logger.js";

const execAsync = promisify(exec);
const log = createLogger("ollama");

export function createOllamaRouter(): Router {
  const router = Router();

  // Check if Ollama is running
  router.get("/ollama/status", authMiddleware, async (_req, res) => {
    try {
      const response = await fetch("http://localhost:11434/");
      const text = await response.text();
      res.json({ running: response.ok, message: text.trim() });
    } catch {
      res.json({ running: false, message: "Ollama is not running" });
    }
  });

  // Start Ollama (install if missing, then start serve)
  router.post("/ollama/start", authMiddleware, async (_req, res) => {
    const platform = os.platform();

    // Check if already running
    try {
      const check = await fetch("http://localhost:11434/");
      if (check.ok) {
        res.json({ ok: true, message: "Ollama is already running" });
        return;
      }
    } catch {}

    // Check if ollama binary exists
    let installed = false;
    try {
      await execAsync("which ollama || where ollama");
      installed = true;
    } catch {}

    if (!installed) {
      // Install Ollama
      try {
        if (platform === "darwin" || platform === "linux") {
          log.info("Installing Ollama via install script...");
          await execAsync("curl -fsSL https://ollama.com/install.sh | sh");
          installed = true;
        } else if (platform === "win32") {
          // On Windows: download and run the installer silently
          log.info("Installing Ollama on Windows...");
          await execAsync(
            `powershell -Command "` +
            `$url = 'https://ollama.com/download/OllamaSetup.exe'; ` +
            `$out = [System.IO.Path]::Combine($env:TEMP, 'OllamaSetup.exe'); ` +
            `Invoke-WebRequest -Uri $url -OutFile $out; ` +
            `Start-Process -FilePath $out -ArgumentList '/S' -Wait"`
          );
          installed = true;
        } else {
          res.status(503).json({ error: "Unsupported platform for auto-install. Install Ollama from https://ollama.com" });
          return;
        }
      } catch (err: any) {
        log.error("Ollama install failed:", err?.message);
        res.status(500).json({
          error: `Ollama installation failed: ${err?.message}. Please install manually from https://ollama.com`,
        });
        return;
      }
    }

    // Start ollama serve as detached background process
    try {
      log.info("Starting ollama serve...");
      const child = spawn("ollama", ["serve"], {
        detached: true,
        stdio: "ignore",
        shell: platform === "win32",
      });
      child.unref();

      // Wait up to 8s for it to come up
      for (let i = 0; i < 16; i++) {
        await new Promise((r) => setTimeout(r, 500));
        try {
          const check = await fetch("http://localhost:11434/");
          if (check.ok) {
            res.json({ ok: true, message: "Ollama started successfully on http://localhost:11434" });
            return;
          }
        } catch {}
      }

      res.status(504).json({ error: "Ollama process started but not responding yet. Try again in a few seconds." });
    } catch (err: any) {
      log.error("ollama serve failed:", err?.message);
      res.status(500).json({ error: `Failed to start Ollama: ${err?.message}` });
    }
  });

  // List locally available models
  router.get("/ollama/models", authMiddleware, async (_req, res) => {
    try {
      const response = await fetch("http://localhost:11434/api/tags");
      if (!response.ok) {
        res.status(503).json({ error: "Ollama not running" });
        return;
      }
      const data = (await response.json()) as any;
      const models = (data.models ?? []).map((m: any) => m.name as string);
      res.json({ models });
    } catch {
      res.status(503).json({ error: "Ollama not running or not reachable at localhost:11434" });
    }
  });

  return router;
}
