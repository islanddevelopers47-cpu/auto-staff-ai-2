# Claw Staffer / Auto Staff AI — Full Project Context

> Hand this file to any AI coding assistant (Cursor, Trae, Windsurf, etc.) so it can pick up work without needing the full conversation history.

---

## 1. What Is This Project?

**Claw Staffer** (also called **Auto Staff AI**) is a multi-platform AI agent management platform. Users create AI "agents" (with system prompts, model providers, skills, temperature, etc.) and deploy them. Agents can reply automatically to Telegram messages, chat inside the app, and execute multi-step tasks.

The project has **five main components** that share a common backend API and data model:

| Component | Tech | Location |
|---|---|---|
| Cloud Backend | Node.js + TypeScript + Express | `auto staff ai Backend/` |
| Web Frontend (SPA) | Vanilla/bundled JS/HTML served by backend | `auto staff ai Backend/public/` |
| macOS Desktop App | Electron wrapping the same backend + frontend | `Auto staff Desktop app/Mac/` |
| Windows Desktop App | Electron wrapping the same backend + frontend | `Auto staff Desktop app/windows/` |
| iOS Mobile App | SwiftUI, named "Claw Mobile" | `IOS/Claw Mobile/` |

---

## 2. Git Repository

Single monorepo at: `https://github.com/islanddevelopers47-cpu/auto-staff-ai-2`  
Default branch: `main`

---

## 3. Cloud Backend (`auto staff ai Backend/`)

### Overview
- **Runtime**: Node.js ≥ 22, TypeScript 5.7
- **Framework**: Express 5
- **Database**: SQLite via `better-sqlite3` (file path configured via `DATABASE_PATH` env var)
- **Auth**: Firebase Admin SDK (Google Sign-In) + JWT for session tokens; bcrypt for local admin password
- **AI**: OpenAI SDK (`openai` npm package) — supports GPT-4o, GPT-4o-mini, GPT-3.5-turbo, etc.
- **Telegram bots**: GrammyJS (`grammy` + `@grammyjs/runner`) — multi-bot manager that wires agents to bots
- **Real-time**: WebSocket server (`ws`) with an `EventBus` for live updates to the frontend
- **Deployment**: Railway (`railway.json` present, Docker also supported)

### Entry Point
`src/index.ts` → initialises DB, Firebase, `AgentRegistry`, `BotManager`, then calls `startServer()`

### Key Source Directories
```
src/
  agents/          # AgentRegistry, skills-loader, run-agent logic
  api/routes/      # All REST API routes (see below)
  auth/            # Firebase middleware, JWT helpers
  database/        # SQLite schema + typed query functions (agents, bots, projects, users…)
  gateway/         # EventBus + WebSocket server
  telegram/        # BotManager — creates/starts/stops grammy bots per agent
  integrations/    # OAuth flows (Google, Notion, etc.)
  utils/           # Logger (tslog)
  config/          # env.ts — reads .env
```

### REST API Routes (`/api/...`)

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/auth/firebase` | Exchange Firebase ID token for a JWT session token |
| GET/POST/PATCH/DELETE | `/api/agents` | CRUD for agents |
| POST | `/api/chat` | Send a message to an agent, get AI reply (`{agentId, message, sessionId?}`) |
| GET/POST/PATCH/DELETE | `/api/projects` | CRUD for projects (multi-agent workspaces) |
| POST | `/api/projects/:id/messages` | Send a message to a project (routes to correct agent) |
| GET/POST/DELETE | `/api/bots` | CRUD for Telegram bots |
| GET/POST | `/api/skills` | List available skills |
| GET/POST | `/api/api-keys` | Manage user API keys |
| GET/POST | `/api/integrations` | OAuth integrations (Google, Notion, etc.) |
| GET | `/api/health` | Health check |

### Environment Variables (`.env`)
```
PORT=3000
HOST=0.0.0.0
NODE_ENV=production
DATABASE_PATH=./data/autostaff.db
JWT_SECRET=<secret>
ADMIN_PASSWORD=admin123
OPENAI_API_KEY=<openai key>
FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json
PUBLIC_URL=https://claw-staffer-production.up.railway.app
```

### Agents & Skills
- Agents are stored in SQLite with fields: `id`, `name`, `description`, `system_prompt`, `model_provider`, `model_name`, `temperature`, `max_tokens`, `skills[]`, `config{}`, `is_builtin`
- Built-in agents are loaded from JSON files in the `agents/` directory at startup
- Skills are TypeScript/JS modules in the `skills/` directory (77 skill files); the agent runner loads them dynamically
- `model_provider` is a string: `"openai"`, `"anthropic"`, `"mlx"`, etc. The backend routes to the appropriate LLM SDK

---

## 4. Web Frontend (SPA)

- Lives in `auto staff ai Backend/public/` as pre-built static files (`index.html` + `assets/`)
- It is a single-page application served by Express
- The backend has an SPA fallback: all non-`/api/` GET requests serve `index.html`
- Also includes `widget.js` — an embeddable chat widget for external websites
- Auth flow: Firebase Google Sign-In → `POST /api/auth/firebase` with ID token → backend returns JWT → stored client-side and sent as `Authorization: Bearer <token>` on every API request

---

## 5. macOS Desktop App (`Auto staff Desktop app/Mac/`)

### Overview
An **Electron app** that bundles the **exact same backend + frontend** code and runs everything locally. No internet connection required for core functionality (Telegram bots still need internet).

### Architecture
- **Electron main process**: `src/main/electron.ts`
  - Finds a free TCP port at startup
  - Sets env vars (`DATABASE_PATH`, `JWT_SECRET`, `PUBLIC_DIR`, `AGENTS_DIR`, `SKILLS_DIR`)
  - Dynamically imports and starts the backend (`src/backend/server.ts`) in the same process
  - Opens a `BrowserWindow` pointing to `http://127.0.0.1:<port>`
- **Preload**: `src/main/preload.ts` (minimal, contextIsolation = true)
- **Backend source**: `src/backend/` — identical code to the cloud backend, with one addition: `src/backend/local/` contains:
  - `shell-executor.ts` — safely executes shell commands (used by agent skills) with safety blocklist, timeout, output cap
  - `file-system.ts` — file read/write/list for agent skills
  - `process-manager.ts` — start/stop/monitor OS processes for agent skills
  - `dependency-checker.ts` — checks if tools like `node`, `python`, `git` are installed

### Build & Package
```bash
cd "Auto staff Desktop app/Mac"
npm install
npm run dev            # dev mode (tsc + electron .)
npm run package        # build .dmg for Mac
npm run package:dmg    # build .dmg only
```

### Key Config
- `appId`: `com.clawstaffer.desktop`
- Window: 1400×900, `hiddenInset` title bar, `#0a0a14` background
- `better-sqlite3` is asar-unpacked (native module)
- Firebase service account: `firebase-service-account.json` in project root (bundled as extraResource)

---

## 6. Windows Desktop App (`Auto staff Desktop app/windows/`)

**Identical architecture to the macOS app**, different Electron build targets:

```bash
cd "Auto staff Desktop app/windows"
npm install
npm run package          # NSIS installer (.exe)
npm run package:nsis     # NSIS installer
npm run package:portable # Portable .exe
npm run package:zip      # ZIP archive
```

- `appId`: `com.clawstaffer.desktop.windows`
- The `src/` directory mirrors the Mac app exactly
- All the same local skills (`shell-executor`, `file-system`, `process-manager`) work on Windows

---

## 7. iOS App (`IOS/Claw Mobile/`)

### Overview
Native **SwiftUI** app named **"Claw Mobile"** / **"ClawMobile"**. Targets iOS 17+. Connects to the Railway cloud backend by default, with optional on-device AI inference via Apple's MLX framework.

### Xcode Project
- Path: `IOS/Claw Mobile/ClawMobile.xcodeproj`
- Bundle ID: (check `Info.plist`)
- Swift Package Dependencies:
  - `mlx-swift-examples` (v2.29.1 from `https://github.com/ml-explore/mlx-swift-examples`) — provides `MLXLLM` and `MLXLMCommon` frameworks for on-device inference

### Source Structure
```
ClawMobile/
  Models/
    Agent.swift          # Agent struct (Codable, Identifiable, Hashable)
    ChatMessage.swift    # ChatMessage struct
    Project.swift        # Project struct
    User.swift           # User struct
  Services/
    APIService.swift     # All REST calls to the Railway backend
    AuthService.swift    # Firebase Auth (Google Sign-In) + JWT exchange
    MLXService.swift     # On-device LLM inference via MLXLLM
    StorageService.swift # Local persistence helpers
  ViewModels/
    AgentViewModel.swift
    ChatViewModel.swift  # Routes messages to MLX or backend
    ProjectViewModel.swift
    AuthViewModel.swift
    SettingsViewModel.swift
  Views/
    Agents/              # Agent list + create/edit
    Chat/                # Chat UI
    Dashboard/           # Home screen
    Projects/            # Project management
    Settings/            # Settings including on-device model management
    Auth/                # Login screen
    MainTabView.swift    # Tab bar (Dashboard, Agents, Projects, Settings)
```

### Backend Connection
- `APIService.swift` hardcodes the base URL:
  ```swift
  private let baseURL = "https://claw-staffer-production.up.railway.app/api"
  ```
  **To change the backend URL, edit this constant.**
- Auth flow: Firebase Google Sign-In → `POST /api/auth/firebase` with Firebase ID token → receive JWT → all subsequent requests include `Authorization: Bearer <jwt>`

### On-Device AI (MLX)
- `MLXService.swift` uses the `MLXLLM` + `MLXLMCommon` Swift packages
- Supported on-device models (downloaded from HuggingFace Hub):
  - Llama 3.2 1B Instruct 4-bit (~700 MB) — `mlx-community/Llama-3.2-1B-Instruct-4bit`
  - Llama 3.2 3B Instruct 4-bit (~1.8 GB)
  - Phi 3.5 Mini Instruct 4-bit (~2.2 GB)
  - Gemma 2 2B Instruct 4-bit (~1.5 GB)
- **Device requirement**: iPhone 15 Pro or newer recommended. Older devices may be very slow or crash.
- Models are downloaded via `LLMModelFactory.shared.loadContainer(configuration:progressHandler:)` which pulls from HuggingFace Hub into the iOS Caches directory
- Inference uses `MLXLMCommon.generate(input:cache:parameters:context:)` which returns `AsyncStream<Generation>` — iterate with `for await generation in stream { if let chunk = generation.chunk { ... } }`

### Chat Routing Logic (`ChatViewModel.swift`)
```swift
// If agent.modelProvider == "mlx" AND a model is loaded → on-device inference
// Otherwise → POST /api/chat to Railway backend
if agent.modelProvider == "mlx" && MLXService.shared.isModelLoaded {
    await sendViaMLX(agent: agent, content: content)
} else {
    await sendViaBackend(agent: agent, content: content)
}
```

---

## 8. Shared Data Model

All platforms use the same agent schema:

| Field | Type | Notes |
|---|---|---|
| `id` | String | UUID |
| `name` | String | Display name |
| `description` | String? | Optional |
| `system_prompt` | String | LLM system prompt |
| `model_provider` | String | `"openai"`, `"anthropic"`, `"mlx"`, etc. |
| `model_name` | String | e.g. `"gpt-4o-mini"`, `"mlx-community/Llama-3.2-1B-Instruct-4bit"` |
| `temperature` | Float | 0.0–2.0 |
| `max_tokens` | Int | e.g. 4096 |
| `skills` | [String] | Array of skill IDs |
| `config` | {String: Any} | Flexible key-value config |
| `is_builtin` | Bool | Built-in agents can't be deleted |

---

## 9. Known Issues / Pending Work

- **iOS build**: MLXService.swift had a series of compile errors (now fixed) related to the MLXLLM API:
  - `@Sendable` closure issues
  - `Chat.Message.Role` enum instead of String
  - `UserInput(chat: [Chat.Message])` constructor (not `UserInput(prompt: .chat(...))`)
  - `MLXLMCommon.generate(input:cache:parameters:context:)` must be called with `cache: nil` explicitly to avoid ambiguity with deprecated overloads, AND must be prefixed with `MLXLMCommon.` because `ModelContext` has an instance method that shadows it
  - `GenerateParameters(maxTokens: Int?, temperature: Float)` — `maxTokens` is `Int?` not `Int`
- **Backend chat route** (`/api/chat`): The `model_provider` field is compared as a string. The route uses `runAgent()` which calls the OpenAI SDK. Non-OpenAI providers need their own SDK branch.
- **Windows app**: Not yet tested end-to-end but mirrors Mac architecture.

---

## 10. How To Run Each Platform

### Cloud Backend
```bash
cd "auto staff ai Backend"
cp .env.example .env   # fill in OPENAI_API_KEY, JWT_SECRET, etc.
npm install
npm run dev            # dev with hot-reload
# OR
npm run build && npm start   # production
```

### macOS Desktop
```bash
cd "Auto staff Desktop app/Mac"
npm install
npm run dev            # dev (tsc + electron)
npm run package        # build .dmg
```

### Windows Desktop
```bash
cd "Auto staff Desktop app/windows"
npm install
npm run dev
npm run package        # NSIS installer
```

### iOS App
1. Open `IOS/Claw Mobile/ClawMobile.xcodeproj` in Xcode 15+
2. Select your device/simulator (on-device MLX requires a real device)
3. Set the team/signing in project settings
4. `⌘B` to build, `⌘R` to run
5. To change backend URL: edit `APIService.swift` line 8 (`baseURL`)

---

## 11. Key Dependencies Summary

| Package | Version | Used In |
|---|---|---|
| express | ^5.1.0 | Backend, Desktop |
| better-sqlite3 | ^11.7.0 | Backend, Desktop |
| grammy | ^1.31.5 | Backend, Desktop (Telegram bots) |
| openai | ^4.77.0 | Backend, Desktop (AI inference) |
| firebase-admin | ^13.6.1 | Backend, Desktop (auth) |
| ws | ^8.18.0 | Backend, Desktop (WebSocket) |
| electron | ^33.3.1 | Desktop apps |
| MLXLLM (Swift pkg) | 2.29.1 | iOS (on-device AI) |
| MLXLMCommon (Swift pkg) | 2.29.1 | iOS (on-device AI) |
| Firebase iOS SDK | (via Xcode) | iOS (Google Sign-In) |
