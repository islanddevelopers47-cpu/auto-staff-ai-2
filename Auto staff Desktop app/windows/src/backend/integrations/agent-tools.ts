import type Database from "better-sqlite3";
import { getConnectedAccount } from "../database/connected-accounts.js";
import * as github from "./github.js";
import * as gdrive from "./google-drive.js";
import * as vercelApi from "./vercel.js";
import * as netlifyApi from "./netlify.js";
import * as dockerApi from "./docker.js";
import { getEnv } from "../config/env.js";
import { resolveIntegrationCred } from "../database/integration-config.js";
import { updateAccessToken } from "../database/connected-accounts.js";
import { createLogger } from "../utils/logger.js";
import { webSearch, webFetch } from "./web-search.js";
import { executeCommand, getSystemInfo, whichBinary } from "../local/shell-executor.js";
import * as localFs from "../local/file-system.js";
import { processManager } from "../local/process-manager.js";
import { checkBinary, checkBinaries, installBinary } from "../local/dependency-checker.js";

const log = createLogger("agent-tools");

// Tool call pattern: [[TOOL:action|param1|param2|...]]
const TOOL_PATTERN = /\[\[TOOL:(\w+)\|([^\]]*)\]\]/g;

export interface ToolResult {
  tool: string;
  success: boolean;
  result: string;
}

/**
 * Build a system prompt section describing available integration tools for this user.
 */
export function buildIntegrationToolsPrompt(db: Database.Database, userId: string): string {
  const ghAccount = getConnectedAccount(db, userId, "github");
  const gdAccount = getConnectedAccount(db, userId, "google_drive");

  const vcAccount = getConnectedAccount(db, userId, "vercel");
  const ntAccount = getConnectedAccount(db, userId, "netlify");
  const env = getEnv();
  const dockerHost = resolveIntegrationCred(db, "docker_host", env.DOCKER_HOST);

  let prompt = "\n\n---\n\n# Tools\n\n";
  prompt += "You have access to tools. To use a tool, output the exact syntax shown below.\n";
  prompt += "The system will execute the tool and provide the result.\n\n";

  // Web tools — always available
  prompt += "## Web Search & Browse\n\n";
  prompt += "Available tools:\n";
  prompt += "- `[[TOOL:web_search|query]]` — Search the web for real-time information. Returns top results with titles, URLs, and snippets.\n";
  prompt += "- `[[TOOL:web_fetch|url]]` — Fetch and read the text content of a web page.\n\n";
  prompt += "Use web_search when the user asks about current events, prices, news, weather, or anything that requires up-to-date information.\n";
  prompt += "Use web_fetch to read the full content of a specific URL from search results.\n\n";

  if (ghAccount) {
    prompt += `## GitHub (connected as @${ghAccount.account_name})\n\n`;
    prompt += "Available tools:\n";
    prompt += "- `[[TOOL:github_list_repos]]` — List all repositories\n";
    prompt += "- `[[TOOL:github_list_files|owner/repo|path]]` — List files in a directory (path can be empty for root)\n";
    prompt += "- `[[TOOL:github_read_file|owner/repo|path]]` — Read a file's contents\n";
    prompt += "- `[[TOOL:github_write_file|owner/repo|path|content|commit message]]` — Create or update a file\n";
    prompt += "- `[[TOOL:github_delete_file|owner/repo|path|sha|commit message]]` — Delete a file (requires sha from read)\n\n";
  }

  if (gdAccount) {
    prompt += `## Google Drive (connected as ${gdAccount.account_name || gdAccount.account_email})\n\n`;
    prompt += "Available tools:\n";
    prompt += "- `[[TOOL:drive_list_files]]` — List files in root\n";
    prompt += "- `[[TOOL:drive_list_folder|folderId]]` — List files in a folder\n";
    prompt += "- `[[TOOL:drive_read_file|fileId]]` — Read a file's contents\n";
    prompt += "- `[[TOOL:drive_create_file|filename|content]]` — Create a new file\n";
    prompt += "- `[[TOOL:drive_update_file|fileId|content]]` — Update an existing file\n";
    prompt += "- `[[TOOL:drive_delete_file|fileId]]` — Delete a file\n\n";
  }

  if (vcAccount) {
    prompt += `## Vercel (connected as @${vcAccount.account_name})\n\n`;
    prompt += "Available tools:\n";
    prompt += "- `[[TOOL:vercel_list_projects]]` — List all Vercel projects\n";
    prompt += "- `[[TOOL:vercel_list_deployments|projectId]]` — List deployments (projectId optional)\n";
    prompt += "- `[[TOOL:vercel_deploy_status|deploymentId]]` — Check deployment status\n";
    prompt += "- `[[TOOL:vercel_deploy|projectName|files_json]]` — Deploy files (files_json is a JSON array of {file,data} objects)\n\n";
  }

  if (ntAccount) {
    prompt += `## Netlify (connected as ${ntAccount.account_name})\n\n`;
    prompt += "Available tools:\n";
    prompt += "- `[[TOOL:netlify_list_sites]]` — List all Netlify sites\n";
    prompt += "- `[[TOOL:netlify_list_deploys|siteId]]` — List deploys for a site\n";
    prompt += "- `[[TOOL:netlify_deploy_status|deployId]]` — Check deploy status\n";
    prompt += "- `[[TOOL:netlify_create_site|name]]` — Create a new site\n";
    prompt += "- `[[TOOL:netlify_deploy|siteId|files_json]]` — Deploy files (files_json is a JSON array of {path,content} objects)\n\n";
  }

  if (dockerHost) {
    prompt += `## Docker (host: ${dockerHost})\n\n`;
    prompt += "Available tools:\n";
    prompt += "- `[[TOOL:docker_list_containers]]` — List all containers\n";
    prompt += "- `[[TOOL:docker_container_logs|containerId|lines]]` — Get container logs (lines defaults to 50)\n";
    prompt += "- `[[TOOL:docker_start|containerId]]` — Start a container\n";
    prompt += "- `[[TOOL:docker_stop|containerId]]` — Stop a container\n";
    prompt += "- `[[TOOL:docker_restart|containerId]]` — Restart a container\n";
    prompt += "- `[[TOOL:docker_list_images]]` — List Docker images\n\n";
  }

  // Local tools — always available on desktop
  prompt += "## Local Shell (Windows Host Machine)\n\n";
  prompt += "You can execute commands directly on the user's Windows PC via PowerShell. Use these tools:\n";
  prompt += "- `[[TOOL:shell_exec|command]]` — Execute a shell command and get the output. Default timeout 30s.\n";
  prompt += "- `[[TOOL:shell_exec_cwd|command|working_directory]]` — Execute a command in a specific directory.\n";
  prompt += "- `[[TOOL:shell_exec_timeout|command|timeout_ms]]` — Execute with a custom timeout (max 300000ms).\n";
  prompt += "- `[[TOOL:which|binary_name]]` — Check if a binary/tool is installed.\n";
  prompt += "- `[[TOOL:system_info]]` — Get system info (OS, arch, username, home dir, shell).\n\n";

  prompt += "## File System\n\n";
  prompt += "You can read and write files on the user's machine:\n";
  prompt += "- `[[TOOL:fs_list|path]]` — List files in a directory (use ~ for home).\n";
  prompt += "- `[[TOOL:fs_list_hidden|path]]` — List files including hidden ones.\n";
  prompt += "- `[[TOOL:fs_read|path]]` — Read a file's contents.\n";
  prompt += "- `[[TOOL:fs_write|path|content]]` — Write content to a file (creates parent dirs).\n";
  prompt += "- `[[TOOL:fs_append|path|content]]` — Append content to a file.\n";
  prompt += "- `[[TOOL:fs_mkdir|path]]` — Create a directory.\n";
  prompt += "- `[[TOOL:fs_delete|path]]` — Delete a file or empty directory.\n";
  prompt += "- `[[TOOL:fs_move|from|to]]` — Move or rename a file/directory.\n";
  prompt += "- `[[TOOL:fs_copy|from|to]]` — Copy a file.\n";
  prompt += "- `[[TOOL:fs_find|directory|pattern]]` — Search for files by name pattern.\n\n";

  prompt += "## Background Processes\n\n";
  prompt += "You can manage long-running background tasks:\n";
  prompt += "- `[[TOOL:proc_start|command]]` — Start a command as a background process.\n";
  prompt += "- `[[TOOL:proc_start_cwd|command|working_directory]]` — Start in a specific directory.\n";
  prompt += "- `[[TOOL:proc_stop|process_id]]` — Stop a background process.\n";
  prompt += "- `[[TOOL:proc_status|process_id]]` — Check process status and recent output.\n";
  prompt += "- `[[TOOL:proc_output|process_id|tail_lines]]` — Get recent output lines.\n";
  prompt += "- `[[TOOL:proc_input|process_id|input_text]]` — Send input to a running process.\n";
  prompt += "- `[[TOOL:proc_list]]` — List all managed background processes.\n\n";

  prompt += "## Dependency Management\n\n";
  prompt += "- `[[TOOL:dep_check|binary_name]]` — Check if a tool/binary is installed.\n";
  prompt += "- `[[TOOL:dep_check_multi|name1,name2,...]]` — Check multiple binaries at once.\n";
  prompt += "- `[[TOOL:dep_install|binary_name]]` — Install a missing tool via winget.\n\n";

  prompt += "**Important rules:**\n";
  prompt += "- You can use multiple tools in sequence (multi-step reasoning). After getting a tool result, decide what to do next.\n";
  prompt += "- When executing commands, explain what you're doing and show the output.\n";
  prompt += "- For destructive operations (delete, overwrite), confirm with the user first unless they've explicitly asked.\n";
  prompt += "- File paths starting with ~ are resolved to the user's home directory.\n";
  prompt += "- The system will execute tools and return results. Use them to complete complex tasks step by step.\n";

  return prompt;
}

/**
 * Detect and execute any tool calls found in the agent's response.
 * Returns the results and the cleaned response.
 */
export async function executeToolCalls(
  db: Database.Database,
  userId: string,
  response: string
): Promise<{ results: ToolResult[]; hasTools: boolean }> {
  const matches = [...response.matchAll(TOOL_PATTERN)];
  if (matches.length === 0) return { results: [], hasTools: false };

  const results: ToolResult[] = [];

  for (const match of matches) {
    const action = match[1]!;
    const params = match[2]!.split("|").map((p) => p.trim());

    try {
      const result = await executeTool(db, userId, action, params);
      results.push({ tool: action, success: true, result });
    } catch (err: any) {
      results.push({ tool: action, success: false, result: `Error: ${err.message}` });
    }
  }

  return { results, hasTools: true };
}

async function executeTool(
  db: Database.Database,
  userId: string,
  action: string,
  params: string[]
): Promise<string> {
  const env = getEnv();

  // GitHub tools
  if (action.startsWith("github_")) {
    const account = getConnectedAccount(db, userId, "github");
    if (!account) return "GitHub is not connected. Please connect GitHub in the Integrations tab.";
    const token = account.access_token;

    switch (action) {
      case "github_list_repos": {
        const repos = await github.listRepos(token);
        const list = repos.slice(0, 30).map((r) => `- ${r.full_name}${r.private ? " (private)" : ""}: ${r.description || "No description"}`);
        return `Found ${repos.length} repositories:\n${list.join("\n")}`;
      }
      case "github_list_files": {
        const [repoFull, filePath = ""] = params;
        if (!repoFull) return "Error: repository is required (e.g., owner/repo)";
        const [owner, repo] = repoFull.split("/");
        if (!owner || !repo) return "Error: invalid repo format. Use owner/repo";
        const files = await github.listFiles(token, owner, repo, filePath);
        const list = files.map((f) => `- ${f.type === "dir" ? "📁" : "📄"} ${f.name}${f.size ? ` (${f.size} bytes)` : ""}`);
        return `Files in ${repoFull}/${filePath || "(root)"}:\n${list.join("\n")}`;
      }
      case "github_read_file": {
        const [repoFull2, filePath2] = params;
        if (!repoFull2 || !filePath2) return "Error: repository and path are required";
        const [owner2, repo2] = repoFull2.split("/");
        if (!owner2 || !repo2) return "Error: invalid repo format. Use owner/repo";
        const file = await github.readFile(token, owner2, repo2, filePath2);
        return `File: ${filePath2} (sha: ${file.sha})\n\`\`\`\n${file.content}\n\`\`\``;
      }
      case "github_write_file": {
        const [repoFull3, filePath3, content, message] = params;
        if (!repoFull3 || !filePath3 || content === undefined) return "Error: repository, path, and content are required";
        const [owner3, repo3] = repoFull3.split("/");
        if (!owner3 || !repo3) return "Error: invalid repo format. Use owner/repo";
        // Try to get existing sha for update
        let sha: string | undefined;
        try {
          const existing = await github.readFile(token, owner3, repo3, filePath3);
          sha = existing.sha;
        } catch { /* new file */ }
        const result = await github.createOrUpdateFile(
          token, owner3, repo3, filePath3, content,
          message || `${sha ? "Update" : "Create"} ${filePath3} via Claw Staffer agent`,
          sha
        );
        return `File ${sha ? "updated" : "created"}: ${filePath3} (sha: ${result.sha})`;
      }
      case "github_delete_file": {
        const [repoFull4, filePath4, sha4, message4] = params;
        if (!repoFull4 || !filePath4 || !sha4) return "Error: repository, path, and sha are required";
        const [owner4, repo4] = repoFull4.split("/");
        if (!owner4 || !repo4) return "Error: invalid repo format. Use owner/repo";
        await github.deleteFile(token, owner4, repo4, filePath4, sha4, message4 || `Delete ${filePath4} via Claw Staffer agent`);
        return `File deleted: ${filePath4}`;
      }
      default:
        return `Unknown GitHub tool: ${action}`;
    }
  }

  // Google Drive tools
  if (action.startsWith("drive_")) {
    const account = getConnectedAccount(db, userId, "google_drive");
    if (!account) return "Google Drive is not connected. Please connect Google Drive in the Integrations tab.";

    // Refresh token if needed
    let token = account.access_token;
    if (account.token_expires_at && new Date(account.token_expires_at) < new Date()) {
      if (!account.refresh_token || !env.GOOGLE_DRIVE_CLIENT_ID || !env.GOOGLE_DRIVE_CLIENT_SECRET) {
        return "Google Drive token expired. Please reconnect in the Integrations tab.";
      }
      const refreshed = await gdrive.refreshAccessToken(env.GOOGLE_DRIVE_CLIENT_ID, env.GOOGLE_DRIVE_CLIENT_SECRET, account.refresh_token);
      const expiresAt = new Date(Date.now() + refreshed.expires_in * 1000).toISOString();
      updateAccessToken(db, account.id, refreshed.access_token, expiresAt);
      token = refreshed.access_token;
    }

    switch (action) {
      case "drive_list_files": {
        const files = await gdrive.listFiles(token);
        const list = files.slice(0, 30).map((f) =>
          `- ${f.mimeType === "application/vnd.google-apps.folder" ? "📁" : "📄"} ${f.name} (id: ${f.id})`
        );
        return `Drive files:\n${list.join("\n")}`;
      }
      case "drive_list_folder": {
        const [folderId] = params;
        if (!folderId) return "Error: folderId is required";
        const files = await gdrive.listFiles(token, folderId);
        const list = files.slice(0, 30).map((f) =>
          `- ${f.mimeType === "application/vnd.google-apps.folder" ? "📁" : "📄"} ${f.name} (id: ${f.id})`
        );
        return `Folder contents:\n${list.join("\n")}`;
      }
      case "drive_read_file": {
        const [fileId] = params;
        if (!fileId) return "Error: fileId is required";
        const file = await gdrive.readFile(token, fileId);
        return `File: ${file.name} (${file.mimeType})\n\`\`\`\n${file.content}\n\`\`\``;
      }
      case "drive_create_file": {
        const [fileName, content = ""] = params;
        if (!fileName) return "Error: filename is required";
        const file = await gdrive.createFile(token, fileName, content);
        return `File created: ${file.name} (id: ${file.id})`;
      }
      case "drive_update_file": {
        const [fileId2, content2] = params;
        if (!fileId2 || content2 === undefined) return "Error: fileId and content are required";
        const file = await gdrive.updateFile(token, fileId2, content2);
        return `File updated: ${file.name} (id: ${file.id})`;
      }
      case "drive_delete_file": {
        const [fileId3] = params;
        if (!fileId3) return "Error: fileId is required";
        await gdrive.deleteFile(token, fileId3);
        return "File deleted successfully.";
      }
      default:
        return `Unknown Drive tool: ${action}`;
    }
  }

  // Vercel tools
  if (action.startsWith("vercel_")) {
    const account = getConnectedAccount(db, userId, "vercel");
    if (!account) return "Vercel is not connected. Please connect Vercel in the Integrations tab.";
    const token = account.access_token;

    switch (action) {
      case "vercel_list_projects": {
        const projects = await vercelApi.listProjects(token);
        const list = projects.slice(0, 30).map((p) => `- ${p.name} (framework: ${p.framework || "none"})`);
        return `Found ${projects.length} Vercel projects:\n${list.join("\n")}`;
      }
      case "vercel_list_deployments": {
        const [projectId] = params;
        const deployments = await vercelApi.listDeployments(token, projectId || undefined);
        const list = deployments.slice(0, 20).map((d) =>
          `- ${d.url} — ${d.state || d.readyState} (${new Date(d.created).toLocaleString()})`
        );
        return `Deployments:\n${list.join("\n")}`;
      }
      case "vercel_deploy_status": {
        const [deploymentId] = params;
        if (!deploymentId) return "Error: deploymentId is required";
        const d = await vercelApi.getDeployment(token, deploymentId);
        return `Deployment ${d.uid}: state=${d.state || d.readyState}, url=${d.url}`;
      }
      case "vercel_deploy": {
        const [name, filesJson] = params;
        if (!name || !filesJson) return "Error: projectName and files_json are required";
        let files: Array<{ file: string; data: string }>;
        try { files = JSON.parse(filesJson); } catch { return "Error: files_json must be valid JSON"; }
        const d = await vercelApi.createDeployment(token, name, files);
        return `Deployed! URL: ${d.url} (uid: ${d.uid}, state: ${d.state || d.readyState})`;
      }
      default:
        return `Unknown Vercel tool: ${action}`;
    }
  }

  // Netlify tools
  if (action.startsWith("netlify_")) {
    const account = getConnectedAccount(db, userId, "netlify");
    if (!account) return "Netlify is not connected. Please connect Netlify in the Integrations tab.";
    const token = account.access_token;

    switch (action) {
      case "netlify_list_sites": {
        const sites = await netlifyApi.listSites(token);
        const list = sites.slice(0, 30).map((s) => `- ${s.name}: ${s.ssl_url || s.url} (id: ${s.id})`);
        return `Found ${sites.length} Netlify sites:\n${list.join("\n")}`;
      }
      case "netlify_list_deploys": {
        const [siteId] = params;
        if (!siteId) return "Error: siteId is required";
        const deploys = await netlifyApi.listDeploys(token, siteId);
        const list = deploys.slice(0, 20).map((d) =>
          `- ${d.id}: ${d.state} — ${d.ssl_url || d.url} (${d.created_at})`
        );
        return `Deploys:\n${list.join("\n")}`;
      }
      case "netlify_deploy_status": {
        const [deployId] = params;
        if (!deployId) return "Error: deployId is required";
        const d = await netlifyApi.getDeployStatus(token, deployId);
        return `Deploy ${d.id}: state=${d.state}, url=${d.ssl_url || d.url}`;
      }
      case "netlify_create_site": {
        const [name] = params;
        const site = await netlifyApi.createSite(token, name || undefined);
        return `Site created: ${site.name} — ${site.ssl_url || site.url} (id: ${site.id})`;
      }
      case "netlify_deploy": {
        const [siteId, filesJson] = params;
        if (!siteId || !filesJson) return "Error: siteId and files_json are required";
        let files: Array<{ path: string; content: string }>;
        try { files = JSON.parse(filesJson); } catch { return "Error: files_json must be valid JSON"; }
        const d = await netlifyApi.deployFiles(token, siteId, files, "Deploy via Claw Staffer agent");
        return `Deployed! URL: ${d.ssl_url || d.url} (id: ${d.id}, state: ${d.state})`;
      }
      default:
        return `Unknown Netlify tool: ${action}`;
    }
  }

  // Docker tools
  if (action.startsWith("docker_")) {
    const env = getEnv();
    const host = resolveIntegrationCred(db, "docker_host", env.DOCKER_HOST) || "http://localhost:2375";

    switch (action) {
      case "docker_list_containers": {
        const containers = await dockerApi.listContainers(host);
        const list = containers.map((c) => {
          const name = c.Names?.[0]?.replace(/^\//, "") || c.Id.slice(0, 12);
          return `- ${name} (${c.Image}) — ${c.State}: ${c.Status}`;
        });
        return `Docker containers:\n${list.join("\n") || "No containers found"}`;
      }
      case "docker_container_logs": {
        const [containerId, lines] = params;
        if (!containerId) return "Error: containerId is required";
        const tail = parseInt(lines || "50", 10);
        const logs = await dockerApi.getContainerLogs(host, containerId, tail);
        return `Logs for ${containerId} (last ${tail} lines):\n\`\`\`\n${logs.slice(0, 4000)}\n\`\`\``;
      }
      case "docker_start": {
        const [containerId] = params;
        if (!containerId) return "Error: containerId is required";
        await dockerApi.startContainer(host, containerId);
        return `Container ${containerId} started.`;
      }
      case "docker_stop": {
        const [containerId] = params;
        if (!containerId) return "Error: containerId is required";
        await dockerApi.stopContainer(host, containerId);
        return `Container ${containerId} stopped.`;
      }
      case "docker_restart": {
        const [containerId] = params;
        if (!containerId) return "Error: containerId is required";
        await dockerApi.restartContainer(host, containerId);
        return `Container ${containerId} restarted.`;
      }
      case "docker_list_images": {
        const images = await dockerApi.listImages(host);
        const list = images.map((i) => {
          const tags = i.RepoTags?.join(", ") || "<none>";
          const sizeMB = (i.Size / 1048576).toFixed(1);
          return `- ${tags} (${sizeMB} MB)`;
        });
        return `Docker images:\n${list.join("\n") || "No images found"}`;
      }
      default:
        return `Unknown Docker tool: ${action}`;
    }
  }

  // Web tools — always available, no account needed
  if (action === "web_search") {
    const query = params[0];
    if (!query) return "Error: search query is required";
    try {
      const results = await webSearch(query);
      if (results.length === 0) return `No results found for: ${query}`;
      const list = results.map((r, i) =>
        `${i + 1}. **${r.title}**\n   ${r.url}\n   ${r.snippet}`
      );
      return `Web search results for "${query}":\n\n${list.join("\n\n")}`;
    } catch (err: any) {
      return `Search error: ${err.message}`;
    }
  }

  if (action === "web_fetch") {
    const targetUrl = params[0];
    if (!targetUrl) return "Error: URL is required";
    try {
      const content = await webFetch(targetUrl);
      if (!content) return `No readable content found at ${targetUrl}`;
      return `Content from ${targetUrl}:\n\n${content}`;
    } catch (err: any) {
      return `Fetch error: ${err.message}`;
    }
  }

  // --- Local Shell tools ---
  if (action === "shell_exec") {
    const cmd = params[0];
    if (!cmd) return "Error: command is required";
    const result = await executeCommand(cmd);
    const output = result.stdout || result.stderr || "(no output)";
    return `Command: ${cmd}\nExit code: ${result.exitCode}${result.killed ? " (killed — timeout)" : ""}\nDuration: ${result.durationMs}ms\n\`\`\`\n${output.slice(0, 8000)}\n\`\`\``;
  }

  if (action === "shell_exec_cwd") {
    const [cmd, cwd] = params;
    if (!cmd) return "Error: command is required";
    const resolvedCwd = (cwd || "").replace(/^~/, process.env.HOME || "");
    const result = await executeCommand(cmd, { cwd: resolvedCwd || undefined });
    const output = result.stdout || result.stderr || "(no output)";
    return `Command: ${cmd}\nCWD: ${resolvedCwd}\nExit code: ${result.exitCode}${result.killed ? " (killed)" : ""}\nDuration: ${result.durationMs}ms\n\`\`\`\n${output.slice(0, 8000)}\n\`\`\``;
  }

  if (action === "shell_exec_timeout") {
    const [cmd, timeoutStr] = params;
    if (!cmd) return "Error: command is required";
    const timeout = parseInt(timeoutStr || "30000", 10);
    const result = await executeCommand(cmd, { timeout });
    const output = result.stdout || result.stderr || "(no output)";
    return `Command: ${cmd}\nExit code: ${result.exitCode}${result.killed ? " (killed — timeout)" : ""}\nDuration: ${result.durationMs}ms\n\`\`\`\n${output.slice(0, 8000)}\n\`\`\``;
  }

  if (action === "which") {
    const name = params[0];
    if (!name) return "Error: binary name is required";
    const binPath = whichBinary(name);
    return binPath ? `${name} found at: ${binPath}` : `${name} is NOT installed`;
  }

  if (action === "system_info") {
    const info = getSystemInfo();
    return Object.entries(info).map(([k, v]) => `${k}: ${v}`).join("\n");
  }

  // --- File System tools ---
  if (action === "fs_list" || action === "fs_list_hidden") {
    const dirPath = (params[0] || "~").replace(/^~/, process.env.HOME || "");
    try {
      const files = localFs.listDirectory(dirPath, action === "fs_list_hidden");
      if (files.length === 0) return `Directory is empty: ${dirPath}`;
      const list = files.map(f => {
        const icon = f.type === "directory" ? "📁" : f.type === "symlink" ? "🔗" : "📄";
        const size = f.type === "file" ? ` (${formatSize(f.size)})` : "";
        return `${icon} ${f.name}${size}`;
      });
      return `Contents of ${dirPath}:\n${list.join("\n")}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_read") {
    const filePath = (params[0] || "").replace(/^~/, process.env.HOME || "");
    if (!filePath) return "Error: file path is required";
    try {
      const file = localFs.readFile(filePath);
      return `File: ${file.path} (${formatSize(file.size)})\n\`\`\`\n${file.content.slice(0, 10000)}\n\`\`\``;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_write") {
    const [filePath, ...contentParts] = params;
    const resolvedPath = (filePath || "").replace(/^~/, process.env.HOME || "");
    if (!resolvedPath) return "Error: file path is required";
    const content = contentParts.join("|"); // rejoin in case content had | chars
    try {
      const result = localFs.writeFile(resolvedPath, content);
      return `Written ${formatSize(result.size)} to ${result.path}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_append") {
    const [filePath, ...contentParts] = params;
    const resolvedPath = (filePath || "").replace(/^~/, process.env.HOME || "");
    if (!resolvedPath) return "Error: file path is required";
    const content = contentParts.join("|");
    try {
      const result = localFs.appendFile(resolvedPath, content);
      return `Appended to ${result.path} (total ${formatSize(result.size)})`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_mkdir") {
    const dirPath = (params[0] || "").replace(/^~/, process.env.HOME || "");
    if (!dirPath) return "Error: directory path is required";
    try {
      const result = localFs.createDirectory(dirPath);
      return `Directory created: ${result.path}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_delete") {
    const targetPath = (params[0] || "").replace(/^~/, process.env.HOME || "");
    if (!targetPath) return "Error: path is required";
    try {
      const result = localFs.deleteItem(targetPath);
      return `Deleted: ${result.path}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_move") {
    const fromPath = (params[0] || "").replace(/^~/, process.env.HOME || "");
    const toPath = (params[1] || "").replace(/^~/, process.env.HOME || "");
    if (!fromPath || !toPath) return "Error: both from and to paths are required";
    try {
      const result = localFs.moveItem(fromPath, toPath);
      return `Moved: ${result.from} → ${result.to}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_copy") {
    const fromPath = (params[0] || "").replace(/^~/, process.env.HOME || "");
    const toPath = (params[1] || "").replace(/^~/, process.env.HOME || "");
    if (!fromPath || !toPath) return "Error: both from and to paths are required";
    try {
      const result = localFs.copyItem(fromPath, toPath);
      return `Copied: ${result.from} → ${result.to}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "fs_find") {
    const dirPath = (params[0] || "~").replace(/^~/, process.env.HOME || "");
    const pattern = params[1];
    if (!pattern) return "Error: search pattern is required";
    try {
      const results = localFs.findFiles(dirPath, pattern);
      if (results.length === 0) return `No files matching '${pattern}' in ${dirPath}`;
      return `Found ${results.length} file(s) matching '${pattern}':\n${results.join("\n")}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  // --- Background Process tools ---
  if (action === "proc_start" || action === "proc_start_cwd") {
    const cmd = params[0];
    if (!cmd) return "Error: command is required";
    const cwd = action === "proc_start_cwd" ? (params[1] || "").replace(/^~/, process.env.HOME || "") : undefined;
    try {
      const proc = processManager.start(cmd, { cwd: cwd || undefined });
      return `Process started:\n  ID: ${proc.id}\n  PID: ${proc.pid}\n  Command: ${proc.command}\n  CWD: ${proc.cwd}\n  Status: ${proc.status}`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "proc_stop") {
    const id = params[0];
    if (!id) return "Error: process_id is required";
    try {
      const stopped = processManager.stop(id);
      return stopped ? `Process ${id} stopped.` : `Process ${id} is not running.`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "proc_status") {
    const id = params[0];
    if (!id) return "Error: process_id is required";
    try {
      const proc = processManager.getProcess(id);
      if (!proc) return `Process not found: ${id}`;
      const output = processManager.getOutput(id, 10);
      let text = `Process ${proc.id}:\n  Command: ${proc.command}\n  PID: ${proc.pid}\n  Status: ${proc.status}\n  Started: ${proc.startedAt}`;
      if (proc.stoppedAt) text += `\n  Stopped: ${proc.stoppedAt}`;
      if (proc.exitCode !== undefined) text += `\n  Exit code: ${proc.exitCode}`;
      if (output.stdout.length > 0) text += `\n  Recent output:\n\`\`\`\n${output.stdout.join("\n")}\n\`\`\``;
      if (output.stderr.length > 0) text += `\n  Recent errors:\n\`\`\`\n${output.stderr.join("\n")}\n\`\`\``;
      return text;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "proc_output") {
    const [id, tailStr] = params;
    if (!id) return "Error: process_id is required";
    try {
      const tail = parseInt(tailStr || "50", 10);
      const output = processManager.getOutput(id, tail);
      const combined = [...output.stdout.map(l => l), ...output.stderr.map(l => `[stderr] ${l}`)];
      return combined.length > 0 ? `Output (last ${tail} lines):\n\`\`\`\n${combined.join("\n")}\n\`\`\`` : "(no output yet)";
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "proc_input") {
    const [id, ...inputParts] = params;
    if (!id) return "Error: process_id is required";
    const input = inputParts.join("|") + "\n";
    try {
      const sent = processManager.sendInput(id, input);
      return sent ? `Sent input to process ${id}` : `Failed to send input (process may not be running)`;
    } catch (err: any) {
      return `Error: ${err.message}`;
    }
  }

  if (action === "proc_list") {
    const procs = processManager.listProcesses();
    if (procs.length === 0) return "No managed processes.";
    const list = procs.map(p =>
      `- ${p.id} [${p.status}] PID:${p.pid} — ${p.command.slice(0, 80)}`
    );
    return `Managed processes (${procs.length}):\n${list.join("\n")}`;
  }

  // --- Dependency tools ---
  if (action === "dep_check") {
    const name = params[0];
    if (!name) return "Error: binary name is required";
    const result = checkBinary(name);
    if (result.found) {
      return `✅ ${name} is installed at ${result.path}${result.version ? ` (${result.version})` : ""}`;
    }
    return `❌ ${name} is NOT installed`;
  }

  if (action === "dep_check_multi") {
    const names = (params[0] || "").split(",").map(s => s.trim()).filter(Boolean);
    if (names.length === 0) return "Error: provide comma-separated binary names";
    const results = checkBinaries(names);
    const lines = results.map(r =>
      r.found ? `✅ ${r.name} — ${r.path}` : `❌ ${r.name} — NOT installed`
    );
    return lines.join("\n");
  }

  if (action === "dep_install") {
    const name = params[0];
    if (!name) return "Error: binary name is required";
    const result = await installBinary(name);
    return result.success ? `✅ ${result.message}` : `❌ ${result.message}`;
  }

  return `Unknown tool: ${action}`;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
}
