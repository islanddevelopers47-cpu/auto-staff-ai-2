import { spawn, execSync } from "node:child_process";
import { createLogger } from "../utils/logger.js";
import os from "node:os";
import path from "node:path";

const log = createLogger("shell-executor");

export interface ShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  killed: boolean;
  durationMs: number;
}

// Configurable safety settings
const MAX_TIMEOUT_MS = 300_000; // 5 minutes max
const MAX_OUTPUT_BYTES = 1_024_000; // ~1MB max output
const DEFAULT_TIMEOUT_MS = 30_000; // 30s default

// Blocked commands for safety
const BLOCKED_PATTERNS = [
  /\brm\s+-rf\s+\/\s*$/,  // rm -rf /
  /\bmkfs\b/,
  /\bdd\s+if=.*of=\/dev\//,
  /:(){ :\|:& };:/,        // fork bomb
  /\bshutdown\b/,
  /\breboot\b/,
  /\bhalt\b/,
  /\binit\s+0\b/,
];

/**
 * Validate a command against safety rules.
 * Returns null if safe, or an error message if blocked.
 */
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

/**
 * Execute a shell command with timeout, output limits, and safety checks.
 */
export async function executeCommand(
  command: string,
  options: {
    cwd?: string;
    timeout?: number;
    env?: Record<string, string>;
    shell?: string;
  } = {}
): Promise<ShellResult> {
  const validationError = validateCommand(command);
  if (validationError) {
    return {
      exitCode: 1,
      stdout: "",
      stderr: validationError,
      killed: false,
      durationMs: 0,
    };
  }

  const timeout = Math.min(options.timeout || DEFAULT_TIMEOUT_MS, MAX_TIMEOUT_MS);
  const cwd = options.cwd || os.homedir();
  const shellPath = options.shell || "/bin/zsh";
  const start = Date.now();

  log.info(`Executing: ${command.slice(0, 200)}${command.length > 200 ? "..." : ""} (cwd: ${cwd}, timeout: ${timeout}ms)`);

  return new Promise<ShellResult>((resolve) => {
    const child = spawn(shellPath, ["-c", command], {
      cwd,
      timeout,
      env: { ...process.env, ...options.env, TERM: "xterm-256color" },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let killed = false;

    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes <= MAX_OUTPUT_BYTES) {
        stdout += chunk.toString("utf-8");
      }
    });

    child.stderr.on("data", (chunk: Buffer) => {
      stderrBytes += chunk.length;
      if (stderrBytes <= MAX_OUTPUT_BYTES) {
        stderr += chunk.toString("utf-8");
      }
    });

    child.on("error", (err) => {
      resolve({
        exitCode: 1,
        stdout,
        stderr: err.message,
        killed: false,
        durationMs: Date.now() - start,
      });
    });

    child.on("close", (code, signal) => {
      killed = signal === "SIGTERM" || signal === "SIGKILL";
      const truncNote = stdoutBytes > MAX_OUTPUT_BYTES
        ? `\n[Output truncated: ${stdoutBytes} bytes total, showing first ${MAX_OUTPUT_BYTES}]`
        : "";

      resolve({
        exitCode: code ?? 1,
        stdout: stdout + truncNote,
        stderr,
        killed,
        durationMs: Date.now() - start,
      });
    });
  });
}

/**
 * Check if a binary exists on the system.
 */
export function whichBinary(name: string): string | null {
  try {
    const result = execSync(`which ${name}`, { encoding: "utf-8", timeout: 5000 }).trim();
    return result || null;
  } catch {
    return null;
  }
}

/**
 * Get basic system info for context.
 */
export function getSystemInfo(): Record<string, string> {
  return {
    platform: os.platform(),
    arch: os.arch(),
    hostname: os.hostname(),
    username: os.userInfo().username,
    homedir: os.homedir(),
    shell: process.env.SHELL || "/bin/zsh",
    nodeVersion: process.version,
    cwd: process.cwd(),
  };
}
