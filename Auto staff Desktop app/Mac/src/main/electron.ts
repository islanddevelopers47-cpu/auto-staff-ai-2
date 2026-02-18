import { app, BrowserWindow, shell, dialog } from "electron";
import path from "node:path";
import fs from "node:fs";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Resolve paths relative to the app
function getResourcePath(...segments: string[]): string {
  // In production, resources are in app.getPath('exe')/../Resources
  // In dev, they are relative to the project root
  const basePath = app.isPackaged
    ? path.join(process.resourcesPath)
    : path.join(__dirname, "..", "..");
  return path.join(basePath, ...segments);
}

function getAppPath(...segments: string[]): string {
  // app.getAppPath() returns the correct root for both dev and packaged (handles asar)
  const basePath = app.isPackaged
    ? app.getAppPath()
    : path.join(__dirname, "..", "..");
  return path.join(basePath, ...segments);
}

// Find a free port
function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      if (addr && typeof addr === "object") {
        const port = addr.port;
        server.close(() => resolve(port));
      } else {
        server.close(() => reject(new Error("Could not find free port")));
      }
    });
    server.on("error", reject);
  });
}

// Ensure data directory exists
function ensureDataDir(): string {
  const dataDir = path.join(app.getPath("userData"), "data");
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
  return dataDir;
}

// Find Firebase service account
function findFirebaseServiceAccount(): string | undefined {
  // Check in resources (bundled)
  const resourcePath = getResourcePath("firebase-service-account.json");
  if (fs.existsSync(resourcePath)) return resourcePath;

  // Check in app directory
  const appPath = getAppPath("firebase-service-account.json");
  if (fs.existsSync(appPath)) return appPath;

  // Auto-detect in app directory
  const appDir = getAppPath();
  if (fs.existsSync(appDir)) {
    const files = fs.readdirSync(appDir).filter(
      (f) => f.includes("firebase-adminsdk") && f.endsWith(".json")
    );
    if (files.length > 0) return path.join(appDir, files[0]);
  }

  return undefined;
}

let mainWindow: BrowserWindow | null = null;
let serverPort: number = 0;
let backendReady = false;

async function startBackend(port: number): Promise<void> {
  const dataDir = ensureDataDir();

  // Set environment variables before importing backend
  process.env.PORT = String(port);
  process.env.HOST = "127.0.0.1";
  process.env.NODE_ENV = "production";
  process.env.DATABASE_PATH = path.join(dataDir, "autostaff.db");
  process.env.JWT_SECRET = process.env.JWT_SECRET || "claw-staffer-desktop-secret-key-2024";
  process.env.ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "admin123";
  process.env.LOG_LEVEL = "info";

  // Firebase service account
  const firebasePath = findFirebaseServiceAccount();
  if (firebasePath) {
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH = firebasePath;
  }

  // Set PUBLIC_URL to localhost for OAuth callbacks
  process.env.PUBLIC_URL = `http://127.0.0.1:${port}`;

  // Set paths so backend can find public/, agents/, skills/
  const appDir = getAppPath();
  process.env.PUBLIC_DIR = getAppPath("public");
  process.env.AGENTS_DIR = getAppPath("agents");
  process.env.SKILLS_DIR = getAppPath("skills");
  try {
    if (fs.existsSync(appDir)) {
      process.chdir(appDir);
    }
  } catch {
    // chdir into asar may fail — env vars above handle it
  }

  // Dynamically import and start the backend
  const { loadEnv } = await import("../backend/config/env.js");
  const { createLogger } = await import("../backend/utils/logger.js");
  const { initDatabase } = await import("../backend/database/db.js");
  const { ensureAdminUser } = await import("../backend/database/users.js");
  const { BotManager } = await import("../backend/telegram/bot-manager.js");
  const { AgentRegistry } = await import("../backend/agents/agent-registry.js");
  const { initFirebase } = await import("../backend/auth/firebase.js");
  const { setAuthDb } = await import("../backend/auth/middleware.js");
  const { startServer } = await import("../backend/server.js");

  loadEnv();
  const log = createLogger("desktop");

  log.info("Starting Claw Staffer Desktop...");
  log.info(`Data directory: ${dataDir}`);
  log.info(`Port: ${port}`);

  const db = initDatabase();
  log.info("Database initialized");

  ensureAdminUser(db);
  log.info("Admin user verified");

  setAuthDb(db);
  const firebaseOk = initFirebase();
  log.info(firebaseOk ? "Firebase auth enabled" : "Firebase auth disabled (no service account)");

  const agentRegistry = new AgentRegistry(db);
  await agentRegistry.loadAgents();
  log.info(`Loaded ${agentRegistry.count()} agents`);

  const botManager = new BotManager(db, agentRegistry);

  await startServer(db, botManager, agentRegistry);
  log.info(`Server listening on port ${port}`);

  await botManager.autoStartBots();
  log.info("Bot manager ready");
  log.info("Claw Staffer Desktop is running!");
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    title: "Claw Staffer",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 16 },
    backgroundColor: "#0a0a14",
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, "preload.js"),
    },
  });

  mainWindow.loadURL(`http://127.0.0.1:${serverPort}`);

  // Open all external links in system browser (including OAuth)
  mainWindow.webContents.setWindowOpenHandler(({ url }: { url: string }) => {
    if (url.startsWith("http")) {
      shell.openExternal(url);
    }
    return { action: "deny" };
  });

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  try {
    serverPort = await findFreePort();
    await startBackend(serverPort);
    backendReady = true;
    createWindow();
  } catch (err: any) {
    dialog.showErrorBox(
      "Claw Staffer — Startup Error",
      `Failed to start the application:\n\n${err.message || err}`
    );
    app.quit();
  }
});

app.on("window-all-closed", () => {
  app.quit();
});

app.on("activate", () => {
  if (mainWindow === null && backendReady) {
    createWindow();
  }
});
