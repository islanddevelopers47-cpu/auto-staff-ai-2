import { execSync } from "node:child_process";
import { createLogger } from "../utils/logger.js";

const log = createLogger("dependency-checker");

export interface BinaryCheck {
  name: string;
  found: boolean;
  path?: string;
  version?: string;
}

export interface InstallResult {
  name: string;
  success: boolean;
  message: string;
}

// Known install commands for popular tools on Debian/Ubuntu Linux
const INSTALL_COMMANDS: Record<string, string> = {
  git: "sudo apt install -y git",
  node: "sudo apt install -y nodejs npm",
  python3: "sudo apt install -y python3",
  pip3: "sudo apt install -y python3-pip",
  ffmpeg: "sudo apt install -y ffmpeg",
  gh: "sudo apt install -y gh || (curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && echo 'deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main' | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install -y gh)",
  jq: "sudo apt install -y jq",
  curl: "sudo apt install -y curl",
  wget: "sudo apt install -y wget",
  ollama: "curl -fsSL https://ollama.com/install.sh | sh",
  docker: "sudo apt install -y docker.io",
  tmux: "sudo apt install -y tmux",
  htop: "sudo apt install -y htop",
  ripgrep: "sudo apt install -y ripgrep",
  fd: "sudo apt install -y fd-find",
  bat: "sudo apt install -y bat",
  fzf: "sudo apt install -y fzf",
  himalaya: "sudo snap install himalaya || cargo install himalaya",
  xdotool: "sudo apt install -y xdotool",
  wmctrl: "sudo apt install -y wmctrl",
  scrot: "sudo apt install -y scrot",
  xclip: "sudo apt install -y xclip",
  xsel: "sudo apt install -y xsel",
};

/**
 * Check if a binary exists and get its version.
 */
export function checkBinary(name: string): BinaryCheck {
  try {
    const binPath = execSync(`which ${name}`, { encoding: "utf-8", timeout: 5000 }).trim();
    let version: string | undefined;
    try {
      // Try common version flags
      version = execSync(`${name} --version 2>/dev/null || ${name} -v 2>/dev/null || ${name} version 2>/dev/null`, {
        encoding: "utf-8",
        timeout: 5000,
      }).trim().split("\n")[0];
    } catch { /* no version info */ }

    return { name, found: true, path: binPath, version };
  } catch {
    return { name, found: false };
  }
}

/**
 * Check multiple binaries at once.
 */
export function checkBinaries(names: string[]): BinaryCheck[] {
  return names.map(checkBinary);
}

/**
 * Check if apt is available (required for most installs on Debian/Ubuntu).
 */
export function hasApt(): boolean {
  try {
    execSync("which apt", { encoding: "utf-8", timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

/**
 * Check if Homebrew is available (kept for compatibility, always false on Linux).
 */
export function hasHomebrew(): boolean {
  return false;
}

/**
 * Get the install command for a binary.
 */
export function getInstallCommand(name: string): string | null {
  return INSTALL_COMMANDS[name] || null;
}

/**
 * Attempt to install a binary using known install methods.
 * Returns the result of the installation attempt.
 */
export async function installBinary(name: string): Promise<InstallResult> {
  const existing = checkBinary(name);
  if (existing.found) {
    return { name, success: true, message: `${name} is already installed at ${existing.path}` };
  }

  const installCmd = getInstallCommand(name);
  if (!installCmd) {
    return { name, success: false, message: `No known install method for '${name}'. Try: brew install ${name}` };
  }

  // Check if apt is needed but not available
  if (installCmd.startsWith("sudo apt ") && !hasApt()) {
    return {
      name,
      success: false,
      message: `apt is required to install ${name} but is not available. This tool is designed for Debian/Ubuntu-based systems.`,
    };
  }

  log.info(`Installing ${name} via: ${installCmd}`);
  try {
    execSync(installCmd, { encoding: "utf-8", timeout: 300_000, stdio: "pipe" });
    const check = checkBinary(name);
    if (check.found) {
      return { name, success: true, message: `Successfully installed ${name} at ${check.path}` };
    }
    return { name, success: false, message: `Install command ran but ${name} not found in PATH` };
  } catch (err: any) {
    return { name, success: false, message: `Install failed: ${err.message?.slice(0, 500)}` };
  }
}

/**
 * Parse a skill's requires.bins field and check availability.
 */
export function checkSkillDependencies(bins: string[]): { satisfied: boolean; missing: BinaryCheck[]; found: BinaryCheck[] } {
  const results = checkBinaries(bins);
  const missing = results.filter((r) => !r.found);
  const found = results.filter((r) => r.found);
  return { satisfied: missing.length === 0, missing, found };
}
