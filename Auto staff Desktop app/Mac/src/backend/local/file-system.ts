import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { createLogger } from "../utils/logger.js";

const log = createLogger("file-system");

export interface FileInfo {
  name: string;
  path: string;
  type: "file" | "directory" | "symlink";
  size: number;
  modified: string;
  permissions: string;
}

export interface FileContent {
  path: string;
  content: string;
  size: number;
  encoding: string;
}

// Safety: restrict file operations to safe directories
const ALLOWED_ROOTS = [
  os.homedir(),
  "/tmp",
  "/var/tmp",
];

function isPathAllowed(targetPath: string): boolean {
  const resolved = path.resolve(targetPath);
  return ALLOWED_ROOTS.some((root) => resolved.startsWith(root));
}

function assertPath(targetPath: string): string {
  const resolved = path.resolve(targetPath);
  if (!isPathAllowed(resolved)) {
    throw new Error(`Access denied: path '${resolved}' is outside allowed directories (${ALLOWED_ROOTS.join(", ")})`);
  }
  return resolved;
}

/**
 * List files and directories at a given path.
 */
export function listDirectory(dirPath: string, showHidden = false): FileInfo[] {
  const resolved = assertPath(dirPath);
  if (!fs.existsSync(resolved)) throw new Error(`Directory not found: ${resolved}`);
  
  const stat = fs.statSync(resolved);
  if (!stat.isDirectory()) throw new Error(`Not a directory: ${resolved}`);

  const entries = fs.readdirSync(resolved, { withFileTypes: true });
  const results: FileInfo[] = [];

  for (const entry of entries) {
    if (!showHidden && entry.name.startsWith(".")) continue;

    const fullPath = path.join(resolved, entry.name);
    try {
      const s = fs.statSync(fullPath);
      results.push({
        name: entry.name,
        path: fullPath,
        type: entry.isDirectory() ? "directory" : entry.isSymbolicLink() ? "symlink" : "file",
        size: s.size,
        modified: s.mtime.toISOString(),
        permissions: (s.mode & 0o777).toString(8),
      });
    } catch {
      // skip entries we can't stat
    }
  }

  return results.sort((a, b) => {
    if (a.type === "directory" && b.type !== "directory") return -1;
    if (a.type !== "directory" && b.type === "directory") return 1;
    return a.name.localeCompare(b.name);
  });
}

/**
 * Read a file's content.
 */
export function readFile(filePath: string, maxBytes = 512_000): FileContent {
  const resolved = assertPath(filePath);
  if (!fs.existsSync(resolved)) throw new Error(`File not found: ${resolved}`);
  
  const stat = fs.statSync(resolved);
  if (stat.isDirectory()) throw new Error(`Path is a directory: ${resolved}`);

  // Check if binary
  const ext = path.extname(resolved).toLowerCase();
  const binaryExts = [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".pdf", ".zip", ".tar", ".gz", ".dmg", ".exe", ".bin", ".so", ".dylib", ".o", ".a"];
  if (binaryExts.includes(ext)) {
    return {
      path: resolved,
      content: `[Binary file: ${stat.size} bytes, type: ${ext}]`,
      size: stat.size,
      encoding: "binary",
    };
  }

  if (stat.size > maxBytes) {
    const partial = fs.readFileSync(resolved, { encoding: "utf-8", flag: "r" }).slice(0, maxBytes);
    return {
      path: resolved,
      content: partial + `\n\n[Truncated: file is ${stat.size} bytes, showing first ${maxBytes}]`,
      size: stat.size,
      encoding: "utf-8",
    };
  }

  return {
    path: resolved,
    content: fs.readFileSync(resolved, "utf-8"),
    size: stat.size,
    encoding: "utf-8",
  };
}

/**
 * Write content to a file, creating parent directories as needed.
 */
export function writeFile(filePath: string, content: string): { path: string; size: number } {
  const resolved = assertPath(filePath);
  const dir = path.dirname(resolved);
  
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    log.info(`Created directory: ${dir}`);
  }

  fs.writeFileSync(resolved, content, "utf-8");
  const stat = fs.statSync(resolved);
  log.info(`Wrote file: ${resolved} (${stat.size} bytes)`);
  
  return { path: resolved, size: stat.size };
}

/**
 * Append content to a file.
 */
export function appendFile(filePath: string, content: string): { path: string; size: number } {
  const resolved = assertPath(filePath);
  fs.appendFileSync(resolved, content, "utf-8");
  const stat = fs.statSync(resolved);
  return { path: resolved, size: stat.size };
}

/**
 * Create a directory.
 */
export function createDirectory(dirPath: string): { path: string } {
  const resolved = assertPath(dirPath);
  fs.mkdirSync(resolved, { recursive: true });
  log.info(`Created directory: ${resolved}`);
  return { path: resolved };
}

/**
 * Delete a file or empty directory.
 */
export function deleteItem(targetPath: string, recursive = false): { path: string; deleted: boolean } {
  const resolved = assertPath(targetPath);
  if (!fs.existsSync(resolved)) throw new Error(`Path not found: ${resolved}`);

  const stat = fs.statSync(resolved);
  if (stat.isDirectory()) {
    if (recursive) {
      fs.rmSync(resolved, { recursive: true, force: true });
    } else {
      fs.rmdirSync(resolved);
    }
  } else {
    fs.unlinkSync(resolved);
  }

  log.info(`Deleted: ${resolved}`);
  return { path: resolved, deleted: true };
}

/**
 * Move/rename a file or directory.
 */
export function moveItem(fromPath: string, toPath: string): { from: string; to: string } {
  const resolvedFrom = assertPath(fromPath);
  const resolvedTo = assertPath(toPath);
  
  if (!fs.existsSync(resolvedFrom)) throw new Error(`Source not found: ${resolvedFrom}`);
  
  const toDir = path.dirname(resolvedTo);
  if (!fs.existsSync(toDir)) {
    fs.mkdirSync(toDir, { recursive: true });
  }

  fs.renameSync(resolvedFrom, resolvedTo);
  log.info(`Moved: ${resolvedFrom} → ${resolvedTo}`);
  return { from: resolvedFrom, to: resolvedTo };
}

/**
 * Copy a file.
 */
export function copyItem(fromPath: string, toPath: string): { from: string; to: string } {
  const resolvedFrom = assertPath(fromPath);
  const resolvedTo = assertPath(toPath);
  
  if (!fs.existsSync(resolvedFrom)) throw new Error(`Source not found: ${resolvedFrom}`);
  
  const toDir = path.dirname(resolvedTo);
  if (!fs.existsSync(toDir)) {
    fs.mkdirSync(toDir, { recursive: true });
  }

  fs.copyFileSync(resolvedFrom, resolvedTo);
  return { from: resolvedFrom, to: resolvedTo };
}

/**
 * Search for files by name pattern (simple glob-like).
 */
export function findFiles(dirPath: string, pattern: string, maxResults = 100): string[] {
  const resolved = assertPath(dirPath);
  if (!fs.existsSync(resolved)) throw new Error(`Directory not found: ${resolved}`);

  const results: string[] = [];
  const regex = new RegExp(pattern.replace(/\*/g, ".*").replace(/\?/g, "."), "i");

  function walk(dir: string, depth: number) {
    if (depth > 8 || results.length >= maxResults) return;
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name.startsWith(".")) continue;
        const full = path.join(dir, entry.name);
        if (regex.test(entry.name)) {
          results.push(full);
        }
        if (entry.isDirectory() && !entry.name.startsWith("node_modules")) {
          walk(full, depth + 1);
        }
      }
    } catch { /* permission denied etc */ }
  }

  walk(resolved, 0);
  return results;
}
