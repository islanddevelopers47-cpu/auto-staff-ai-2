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

// Known install commands for popular tools on macOS
const INSTALL_COMMANDS: Record<string, string> = {
  brew: '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
  git: "xcode-select --install",
  node: "brew install node",
  python3: "brew install python3",
  pip3: "brew install python3",
  ffmpeg: "brew install ffmpeg",
  gh: "brew install gh",
  jq: "brew install jq",
  curl: "brew install curl",
  wget: "brew install wget",
  ollama: "brew install ollama",
  docker: "brew install --cask docker",
  tmux: "brew install tmux",
  htop: "brew install htop",
  ripgrep: "brew install ripgrep",
  fd: "brew install fd",
  bat: "brew install bat",
  fzf: "brew install fzf",
  himalaya: "brew install himalaya",
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
 * Check if Homebrew is available (required for most installs).
 */
export function hasHomebrew(): boolean {
  try {
    execSync("which brew", { encoding: "utf-8", timeout: 5000 });
    return true;
  } catch {
    return false;
  }
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

  // Check if brew is needed but not available
  if (installCmd.startsWith("brew ") && !hasHomebrew()) {
    return {
      name,
      success: false,
      message: `Homebrew is required to install ${name} but is not installed. Install it first: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`,
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
