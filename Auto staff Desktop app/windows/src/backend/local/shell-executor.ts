import { spawn, execSync } from "node:child_process";
import { createLogger } from "../utils/logger.js";
import os from "node:os";

const log = createLogger("shell-executor");

export interface ShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  killed: boolean;
  durationMs: number;
}

const MAX_TIMEOUT_MS = 300_000;
const MAX_OUTPUT_BYTES = 1_024_000;
const DEFAULT_TIMEOUT_MS = 30_000;

const BLOCKED_PATTERNS = [
  /\bFormat-Volume\b/i,
  /\bClear-Disk\b/i,
  /\bRemove-Item\s+-Recurse\s+-Force\s+[A-Z]:\\\s*$/i,
  /\brd\s+\/s\s+\/q\s+[A-Z]:\\\s*$/i,
  /\bStop-Computer\b/i,
  /\bRestart-Computer\b/i,
  /\bshutdown\s+\/s/i,
  /\bshutdown\s+\/r/i,
  /\bdel\s+\/f\s+\/s\s+\/q\s+[A-Z]:\\\s*$/i,
];

export function validateCommand(command: string): string | null {
  const trimmed = command.trim();
  if (!trimmed) return "Empty command";
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(trimmed)) {
      return `Blocked: command matches dangerous pattern (${pattern.source})`;
    }
  }
  return null;
}

export async function executeCommand(
  command: string,
  options: { cwd?: string; timeout?: number; env?: Record<string, string>; shell?: string } = {}
): Promise<ShellResult> {
  const validationError = validateCommand(command);
  if (validationError) {
    return { exitCode: 1, stdout: "", stderr: validationError, killed: false, durationMs: 0 };
  }

  const timeout = Math.min(options.timeout || DEFAULT_TIMEOUT_MS, MAX_TIMEOUT_MS);
  const cwd = options.cwd || os.homedir();
  const shellPath = options.shell || "powershell.exe";
  const shellArgs = shellPath.includes("powershell") || shellPath.includes("pwsh")
    ? ["-NoProfile", "-NonInteractive", "-Command", command]
    : ["/c", command];
  const start = Date.now();

  log.info(`Executing: ${command.slice(0, 200)}${command.length > 200 ? "..." : ""} (cwd: ${cwd}, timeout: ${timeout}ms)`);

  return new Promise<ShellResult>((resolve) => {
    const child = spawn(shellPath, shellArgs, {
      cwd, timeout,
      env: { ...process.env, ...options.env },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "", stderr = "";
    let stdoutBytes = 0, stderrBytes = 0, killed = false;

    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes <= MAX_OUTPUT_BYTES) stdout += chunk.toString("utf-8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderrBytes += chunk.length;
      if (stderrBytes <= MAX_OUTPUT_BYTES) stderr += chunk.toString("utf-8");
    });
    child.on("error", (err) => {
      resolve({ exitCode: 1, stdout, stderr: err.message, killed: false, durationMs: Date.now() - start });
    });
    child.on("close", (code) => {
      killed = code === null;
      const truncNote = stdoutBytes > MAX_OUTPUT_BYTES
        ? `\n[Output truncated: ${stdoutBytes} bytes total, showing first ${MAX_OUTPUT_BYTES}]` : "";
      resolve({ exitCode: code ?? 1, stdout: stdout + truncNote, stderr, killed, durationMs: Date.now() - start });
    });
  });
}

export function whichBinary(name: string): string | null {
  try {
    const result = execSync(`where.exe ${name}`, { encoding: "utf-8", timeout: 5000 }).trim().split("\n")[0].trim();
    return result || null;
  } catch { return null; }
}

export function getSystemInfo(): Record<string, string> {
  return {
    platform: os.platform(),
    arch: os.arch(),
    hostname: os.hostname(),
    username: os.userInfo().username,
    homedir: os.homedir(),
    shell: process.env.COMSPEC || "powershell.exe",
    nodeVersion: process.version,
    cwd: process.cwd(),
  };
}
