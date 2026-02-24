import type Database from "better-sqlite3";
import type { Agent } from "../database/agents.js";
import {
  chatCompletion,
  type ChatMessage,
  type ProviderName,
} from "./model-providers.js";
import {
  findOrCreateSession,
  getSessionHistory,
  addMessage,
  updateSessionTimestamp,
} from "../database/sessions.js";
import { buildSkillsPrompt } from "./skills-loader.js";
import { buildIntegrationToolsPrompt, executeToolCalls, captureCurrentScreen } from "../integrations/agent-tools.js";
import { createLogger } from "../utils/logger.js";

const log = createLogger("agent-runner");

export interface RunAgentInput {
  botId: string | null;
  chatId: string;
  chatType: "private" | "group" | "supergroup" | "channel";
  userMessage: string;
  telegramMessageId?: number;
  senderName?: string;
  apiKeyOverride?: string;
  providerOverride?: ProviderName;
  modelOverride?: string;
  userId?: string;
}

export interface RunAgentResult {
  response: string;
  sessionId: string;
  model: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

export async function runAgent(
  db: Database.Database,
  agent: Agent,
  input: RunAgentInput
): Promise<RunAgentResult> {
  // Find or create session
  const session = findOrCreateSession(
    db,
    input.botId,
    input.chatId,
    input.chatType,
    agent.id
  );

  // Save user message
  addMessage(db, session.id, "user", input.userMessage, input.telegramMessageId, {
    senderName: input.senderName,
  });

  // Get conversation history
  const historyLimit = getHistoryLimit(agent);
  const history = getSessionHistory(db, session.id, historyLimit);

  // Determine effective provider/model early (needed for monitor-mode vision injection)
  const effectiveProvider = input.providerOverride ?? (agent.model_provider as ProviderName);
  const effectiveModel = input.modelOverride ?? agent.model_name;

  // Build messages array for the LLM
  let systemPrompt = buildSystemPrompt(agent, input);

  // Add tools context (web tools always available; integration tools if user has connected accounts)
  const toolsPrompt = buildIntegrationToolsPrompt(db, input.userId || "");
  if (toolsPrompt) systemPrompt += toolsPrompt;

  // Monitor mode: auto-capture screen and inject into context before every turn
  const agentSkillsList = (() => { try { return JSON.parse(agent.skills) as string[]; } catch { return [] as string[]; } })();
  let monitorScreenshot: { path: string; base64: string } | null = null;
  if (agentSkillsList.includes("monitor-mode")) {
    monitorScreenshot = await captureCurrentScreen();
    if (monitorScreenshot) {
      systemPrompt +=
        `\n\n## Monitor Mode — Live Screen Feed Active\n` +
        `A fresh screenshot of the current screen is automatically captured before every message turn. ` +
        `You can see the live state of the desktop. Use screen_control tools (screen_mouse_click, screen_key, screen_type, screen_scroll, screen_mouse_move) to interact with it. ` +
        `You do NOT need to call [[TOOL:screen_capture]] — the screen state is already provided to you.\n` +
        `Current screen captured at: ${new Date().toISOString()}`;
    }
  }

  const messages: ChatMessage[] = [
    { role: "system", content: systemPrompt },
  ];

  for (const msg of history) {
    messages.push({
      role: msg.role as "user" | "assistant",
      content: msg.content,
    });
  }

  // For vision-capable providers, inject the monitor screenshot as an image in the latest user turn
  if (monitorScreenshot && ["openai", "anthropic", "google"].includes(effectiveProvider)) {
    const lastUserIdx = messages.map(m => m.role).lastIndexOf("user");
    if (lastUserIdx >= 0) {
      const originalText = messages[lastUserIdx].content as string;
      messages[lastUserIdx] = {
        role: "user",
        content: [
          { type: "text", text: `[Monitor Mode — current screen]:` },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${monitorScreenshot.base64}` } },
          { type: "text", text: originalText },
        ] as any,
      };
    }
  }

  // Call the LLM
  log.info(
    `Running agent "${agent.name}" (${effectiveProvider}/${effectiveModel}) for chat ${input.chatId}`
  );

  try {
    const result = await chatCompletion(
      effectiveProvider,
      {
        model: effectiveModel,
        messages,
        temperature: agent.temperature,
        maxTokens: agent.max_tokens,
      },
      input.apiKeyOverride
    );

    let finalContent = result.content;

    // Multi-step tool loop — agent can chain up to 10 tool calls
    {
      let toolRound = 0;
      const maxRounds = 10;
      let currentContent = result.content;
      while (toolRound < maxRounds) {
        const { results: toolResults, hasTools } = await executeToolCalls(db, input.userId || "", currentContent);
        if (!hasTools) break;

        log.info(`Tool round ${toolRound + 1}: executed ${toolResults.length} tool(s) — ${toolResults.map(r => r.tool).join(", ")}`);

        // Add tool results to conversation and get follow-up
        const toolResultText = toolResults.map(r =>
          `[Tool Result: ${r.tool}] ${r.success ? "✅ " : "❌ ERROR: "}${r.result}`
        ).join("\n\n");

        messages.push({ role: "assistant", content: currentContent });
        messages.push({ role: "user", content: `Tool execution results:\n\n${toolResultText}\n\nContinue with your plan. If you need to use more tools, do so. If you're done, provide your final response to the user.` });

        const followUp = await chatCompletion(
          effectiveProvider,
          { model: effectiveModel, messages, temperature: agent.temperature, maxTokens: agent.max_tokens },
          input.apiKeyOverride
        );
        currentContent = followUp.content;
        toolRound++;
      }
      if (toolRound >= maxRounds) {
        currentContent += "\n\n*(Reached maximum tool execution rounds)*";
      }
      finalContent = currentContent;
    }

    // Save assistant response and bump session timestamp
    addMessage(db, session.id, "assistant", finalContent);
    updateSessionTimestamp(db, session.id);

    return {
      response: finalContent,
      sessionId: session.id,
      model: result.model,
      usage: result.usage,
    };
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    log.error(`Agent run failed: ${errorMsg}`);
    throw err;
  }
}

function buildSystemPrompt(agent: Agent, input: RunAgentInput): string {
  let prompt = agent.system_prompt;

  // Add context
  const now = new Date().toISOString();
  prompt += `\n\nCurrent date and time: ${now}`;

  if (input.senderName) {
    prompt += `\nYou are talking to: ${input.senderName}`;
  }

  if (input.chatType === "group" || input.chatType === "supergroup") {
    prompt += "\nThis is a group chat. Keep responses relevant and concise.";
  }

  // Add skills context
  try {
    const skills = JSON.parse(agent.skills) as string[];
    if (skills.length > 0) {
      const skillsPrompt = buildSkillsPrompt(skills);
      if (skillsPrompt) {
        prompt += skillsPrompt;
      }
    }
  } catch {
    // ignore
  }

  return prompt;
}

function getHistoryLimit(agent: Agent): number {
  try {
    const config = JSON.parse(agent.config) as Record<string, unknown>;
    if (typeof config.historyLimit === "number") {
      return config.historyLimit;
    }
  } catch {
    // ignore
  }
  return 50;
}
