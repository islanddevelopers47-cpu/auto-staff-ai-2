import type Database from "better-sqlite3";
import {
  findAgentById,
  listAgents,
  countAgents,
  type Agent,
} from "../database/agents.js";
import { loadSkillsFromDir } from "./skills-loader.js";
import { createLogger } from "../utils/logger.js";

const log = createLogger("agent-registry");

export class AgentRegistry {
  private db: Database.Database;
  private agentCache: Map<string, Agent> = new Map();

  constructor(db: Database.Database) {
    this.db = db;
  }

  async loadAgents(): Promise<void> {
    // Load skills from the skills directory
    const skills = loadSkillsFromDir();
    log.info(`Loaded ${skills.length} skills`);

    // Load built-in agents from JSON files
    await this.loadBuiltinAgents();

    // Refresh cache
    this.refreshCache();
  }

  private async loadBuiltinAgents(): Promise<void> {
    // Remove ALL built-in agents from DB — agents must be added manually
    const builtins = this.db
      .prepare("SELECT id, name FROM agents WHERE is_builtin = 1")
      .all() as { id: string; name: string }[];
    for (const agent of builtins) {
      this.db.prepare("DELETE FROM agents WHERE id = ?").run(agent.id);
      log.info(`Removed built-in agent: ${agent.name}`);
    }
  }

  private refreshCache(): void {
    this.agentCache.clear();
    const agents = listAgents(this.db);
    for (const agent of agents) {
      this.agentCache.set(agent.id, agent);
    }
  }

  getAgent(id: string): Agent | undefined {
    // Check cache first
    const cached = this.agentCache.get(id);
    if (cached) return cached;

    // Fall back to DB
    const agent = findAgentById(this.db, id);
    if (agent) {
      this.agentCache.set(agent.id, agent);
    }
    return agent;
  }

  getDefaultAgent(): Agent | undefined {
    const agents = listAgents(this.db);
    return agents[0];
  }

  getAllAgents(): Agent[] {
    return listAgents(this.db);
  }

  count(): number {
    return countAgents(this.db);
  }

  invalidateCache(): void {
    this.agentCache.clear();
  }
}
