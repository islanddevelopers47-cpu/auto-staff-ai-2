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

// Known install commands for popular tools on Windows (winget preferred, choco fallback)
const INSTALL_COMMANDS: Record<string, string> = {
  git: "winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements",
  node: "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements",
  python3: "winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements",
  python: "winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements",
  pip3: "winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements",
  ffmpeg: "winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements",
  gh: "winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements",
  jq: "winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements",
  curl: "winget install --id cURL.cURL -e --accept-source-agreements --accept-package-agreements",
  wget: "winget install --id JernejSimoncic.Wget -e --accept-source-agreements --accept-package-agreements",
  ollama: "winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements",
  docker: "winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements",
  ripgrep: "winget install --id BurntSushi.ripgrep.MSVC -e --accept-source-agreements --accept-package-agreements",
  fd: "winget install --id sharkdp.fd -e --accept-source-agreements --accept-package-agreements",
  bat: "winget install --id sharkdp.bat -e --accept-source-agreements --accept-package-agreements",
  fzf: "winget install --id junegunn.fzf -e --accept-source-agreements --accept-package-agreements",
  code: "winget install --id Microsoft.VisualStudioCode -e --accept-source-agreements --accept-package-agreements",
  wt: "winget install --id Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements",
};

export function checkBinary(name: string): BinaryCheck {
  try {
    const binPath = execSync(`where.exe ${name}`, { encoding: "utf-8", timeout: 5000 }).trim().split("\n")[0].trim();
    let version: string | undefined;
    try {
      version = execSync(`powershell.exe -NoProfile -Command "& { try { & '${name}' --version 2>$null } catch {} }"`, {
        encoding: "utf-8", timeout: 5000,
      }).trim().split("\n")[0];
    } catch { /* no version info */ }
    return { name, found: true, path: binPath, version };
  } catch {
    return { name, found: false };
  }
}

export function checkBinaries(names: string[]): BinaryCheck[] {
  return names.map(checkBinary);
}

export function hasWinget(): boolean {
  try {
    execSync("where.exe winget", { encoding: "utf-8", timeout: 5000 });
    return true;
  } catch { return false; }
}

export function hasChocolatey(): boolean {
  try {
    execSync("where.exe choco", { encoding: "utf-8", timeout: 5000 });
    return true;
  } catch { return false; }
}

export function getInstallCommand(name: string): string | null {
  return INSTALL_COMMANDS[name] || null;
}

export async function installBinary(name: string): Promise<InstallResult> {
  const existing = checkBinary(name);
  if (existing.found) {
    return { name, success: true, message: `${name} is already installed at ${existing.path}` };
  }

  const installCmd = getInstallCommand(name);
  if (!installCmd) {
    return { name, success: false, message: `No known install method for '${name}'. Try: winget install ${name}` };
  }

  // Check if winget is available
  if (installCmd.startsWith("winget ") && !hasWinget()) {
    return {
      name, success: false,
      message: `winget is required to install ${name} but is not available. Please update your Windows or install App Installer from the Microsoft Store.`,
    };
  }

  log.info(`Installing ${name} via: ${installCmd}`);
  try {
    execSync(installCmd, { encoding: "utf-8", timeout: 300_000, stdio: "pipe" });
    const check = checkBinary(name);
    if (check.found) {
      return { name, success: true, message: `Successfully installed ${name} at ${check.path}` };
    }
    return { name, success: false, message: `Install command ran but ${name} not found in PATH. You may need to restart the app.` };
  } catch (err: any) {
    return { name, success: false, message: `Install failed: ${err.message?.slice(0, 500)}` };
  }
}

export function checkSkillDependencies(bins: string[]): { satisfied: boolean; missing: BinaryCheck[]; found: BinaryCheck[] } {
  const results = checkBinaries(bins);
  const missing = results.filter((r) => !r.found);
  const found = results.filter((r) => r.found);
  return { satisfied: missing.length === 0, missing, found };
}
