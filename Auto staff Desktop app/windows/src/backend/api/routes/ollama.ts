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

  // Start Ollama (launch if installed, install only if truly missing)
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

    // Detect if Ollama is installed — check all common locations
    // (Electron's PATH may not include /usr/local/bin, so check explicitly)
    const macAppPath = "/Applications/Ollama.app";
    const commonBinPaths = [
      "/usr/local/bin/ollama",
      "/usr/bin/ollama",
      `${os.homedir()}/.ollama/bin/ollama`,
      `${os.homedir()}/bin/ollama`,
    ];
    const winPaths = [
      `${process.env["LOCALAPPDATA"] ?? ""}\\Programs\\Ollama\\ollama.exe`,
      `${process.env["ProgramFiles"] ?? ""}\\Ollama\\ollama.exe`,
    ];

    let ollamaBin: string | null = null;
    let ollamaIsApp = false; // macOS .app launch

    if (platform === "darwin") {
      const { existsSync } = await import("node:fs");
      if (existsSync(macAppPath)) {
        ollamaIsApp = true;
      } else {
        for (const p of commonBinPaths) {
          if (existsSync(p)) { ollamaBin = p; break; }
        }
        // Also try PATH lookup
        if (!ollamaBin) {
          try { await execAsync("/usr/bin/which ollama"); ollamaBin = "ollama"; } catch {}
        }
      }
    } else if (platform === "win32") {
      const { existsSync } = await import("node:fs");
      for (const p of winPaths) {
        if (p && existsSync(p)) { ollamaBin = p; break; }
      }
      if (!ollamaBin) {
        try { await execAsync("where ollama"); ollamaBin = "ollama"; } catch {}
      }
    } else {
      // Linux
      try { await execAsync("which ollama"); ollamaBin = "ollama"; } catch {}
    }

    const isInstalled = ollamaIsApp || !!ollamaBin;

    if (!isInstalled) {
      // Only install if truly not found anywhere
      try {
        if (platform === "darwin" || platform === "linux") {
          log.info("Ollama not found, installing via install script...");
          await execAsync("curl -fsSL https://ollama.com/install.sh | sh", {
            env: { ...process.env, PATH: `/usr/local/bin:/usr/bin:/bin:${process.env["PATH"] ?? ""}` },
          });
          ollamaBin = "ollama";
        } else if (platform === "win32") {
          log.info("Ollama not found, installing on Windows...");
          await execAsync(
            `powershell -Command "` +
            `$url = 'https://ollama.com/download/OllamaSetup.exe'; ` +
            `$out = [System.IO.Path]::Combine($env:TEMP, 'OllamaSetup.exe'); ` +
            `Invoke-WebRequest -Uri $url -OutFile $out; ` +
            `Start-Process -FilePath $out -ArgumentList '/S' -Wait"`
          );
          ollamaBin = "ollama";
        } else {
          res.status(503).json({ error: "Unsupported platform. Install Ollama from https://ollama.com" });
          return;
        }
      } catch (err: any) {
        log.error("Ollama install failed:", err?.message);
        res.status(500).json({
          error: `Ollama not found and auto-install failed. Please install manually from https://ollama.com\n\nError: ${err?.message}`,
        });
        return;
      }
    }

    // Launch Ollama
    try {
      if (ollamaIsApp) {
        // macOS: launch the .app (it starts the server automatically)
        log.info("Launching Ollama.app via open command...");
        const child = spawn("open", ["-a", "Ollama"], { detached: true, stdio: "ignore" });
        child.unref();
      } else {
        // CLI binary: run ollama serve
        log.info(`Starting ollama serve (bin: ${ollamaBin})...`);
        const bin = ollamaBin ?? "ollama";
        const child = spawn(bin, ["serve"], {
          detached: true,
          stdio: "ignore",
          shell: platform === "win32",
          env: { ...process.env, PATH: `/usr/local/bin:/usr/bin:/bin:${process.env["PATH"] ?? ""}` },
        });
        child.unref();
      }

      // Wait up to 10s for the server to come up
      for (let i = 0; i < 20; i++) {
        await new Promise((r) => setTimeout(r, 500));
        try {
          const check = await fetch("http://localhost:11434/");
          if (check.ok) {
            res.json({ ok: true, message: "Ollama started successfully on http://localhost:11434" });
            return;
          }
        } catch {}
      }

      res.status(504).json({ error: "Ollama launched but not responding yet. Give it a few more seconds and try again." });
    } catch (err: any) {
      log.error("Ollama launch failed:", err?.message);
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
