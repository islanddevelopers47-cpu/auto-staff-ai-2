import { spawn, type ChildProcess } from "node:child_process";
import os from "node:os";
import { createLogger } from "../utils/logger.js";
import { EventEmitter } from "node:events";

const log = createLogger("process-manager");

export interface ManagedProcess {
  id: string;
  command: string;
  cwd: string;
  pid: number | undefined;
  status: "running" | "stopped" | "error" | "completed";
  startedAt: string;
  stoppedAt?: string;
  exitCode?: number | null;
  outputLines: string[];
  errorLines: string[];
}

interface ProcessEntry {
  child: ChildProcess;
  info: ManagedProcess;
  maxOutputLines: number;
}

const MAX_PROCESSES = 20;
const MAX_OUTPUT_LINES = 500;

class ProcessManager extends EventEmitter {
  private processes = new Map<string, ProcessEntry>();
  private idCounter = 0;

  start(
    command: string,
    options: { cwd?: string; env?: Record<string, string>; shell?: string } = {}
  ): ManagedProcess {
    if (this.processes.size >= MAX_PROCESSES) {
      for (const [id, entry] of this.processes) {
        if (entry.info.status !== "running") this.processes.delete(id);
      }
      if (this.processes.size >= MAX_PROCESSES) {
        throw new Error(`Too many processes (max ${MAX_PROCESSES}). Stop some first.`);
      }
    }

    const id = `proc_${++this.idCounter}_${Date.now()}`;
    const cwd = options.cwd || os.homedir();
    const shellPath = options.shell || "powershell.exe";
    const shellArgs = shellPath.includes("powershell") || shellPath.includes("pwsh")
      ? ["-NoProfile", "-Command", command]
      : ["/c", command];

    const child = spawn(shellPath, shellArgs, {
      cwd,
      env: { ...process.env, ...options.env },
      stdio: ["pipe", "pipe", "pipe"],
      detached: false,
    });

    const info: ManagedProcess = {
      id, command, cwd,
      pid: child.pid,
      status: "running",
      startedAt: new Date().toISOString(),
      outputLines: [],
      errorLines: [],
    };

    const entry: ProcessEntry = { child, info, maxOutputLines: MAX_OUTPUT_LINES };
    this.processes.set(id, entry);

    child.stdout?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString("utf-8").split("\n").filter(Boolean);
      for (const line of lines) {
        if (info.outputLines.length >= entry.maxOutputLines) info.outputLines.shift();
        info.outputLines.push(line);
      }
      this.emit("output", { id, type: "stdout", data: chunk.toString("utf-8") });
    });

    child.stderr?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString("utf-8").split("\n").filter(Boolean);
      for (const line of lines) {
        if (info.errorLines.length >= entry.maxOutputLines) info.errorLines.shift();
        info.errorLines.push(line);
      }
      this.emit("output", { id, type: "stderr", data: chunk.toString("utf-8") });
    });

    child.on("close", (code, signal) => {
      info.status = code === 0 ? "completed" : "error";
      info.exitCode = code;
      info.stoppedAt = new Date().toISOString();
      this.emit("exit", { id, code, signal });
      log.info(`Process ${id} (pid ${info.pid}) exited with code ${code}`);
    });

    child.on("error", (err) => {
      info.status = "error";
      info.stoppedAt = new Date().toISOString();
      info.errorLines.push(`Process error: ${err.message}`);
      this.emit("error", { id, error: err.message });
      log.error(`Process ${id} error: ${err.message}`);
    });

    log.info(`Started process ${id}: ${command} (pid: ${child.pid}, cwd: ${cwd})`);
    return { ...info };
  }

  stop(id: string, signal: NodeJS.Signals = "SIGTERM"): boolean {
    const entry = this.processes.get(id);
    if (!entry) throw new Error(`Process not found: ${id}`);
    if (entry.info.status !== "running") return false;
    try {
      entry.child.kill(signal);
      entry.info.status = "stopped";
      entry.info.stoppedAt = new Date().toISOString();
      log.info(`Stopped process ${id} (signal: ${signal})`);
      return true;
    } catch (err: any) {
      log.error(`Failed to stop process ${id}: ${err.message}`);
      return false;
    }
  }

  sendInput(id: string, input: string): boolean {
    const entry = this.processes.get(id);
    if (!entry) throw new Error(`Process not found: ${id}`);
    if (entry.info.status !== "running") return false;
    try { entry.child.stdin?.write(input); return true; } catch { return false; }
  }

  getProcess(id: string): ManagedProcess | null {
    const entry = this.processes.get(id);
    return entry ? { ...entry.info } : null;
  }

  getOutput(id: string, tail = 50): { stdout: string[]; stderr: string[] } {
    const entry = this.processes.get(id);
    if (!entry) throw new Error(`Process not found: ${id}`);
    return { stdout: entry.info.outputLines.slice(-tail), stderr: entry.info.errorLines.slice(-tail) };
  }

  listProcesses(): ManagedProcess[] {
    return Array.from(this.processes.values()).map((e) => ({ ...e.info }));
  }

  remove(id: string): boolean {
    const entry = this.processes.get(id);
    if (!entry) return false;
    if (entry.info.status === "running") this.stop(id);
    return this.processes.delete(id);
  }

  stopAll(): void {
    for (const [id, entry] of this.processes) {
      if (entry.info.status === "running") {
        try { entry.child.kill("SIGTERM"); } catch { /* ignore */ }
      }
    }
    this.processes.clear();
    log.info("All processes stopped");
  }
}

export const processManager = new ProcessManager();
