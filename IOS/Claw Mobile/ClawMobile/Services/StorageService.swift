import Foundation

/// Local storage service for caching data offline using UserDefaults and file system
class StorageService {
    static let shared = StorageService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Agents Cache

    func cacheAgents(_ agents: [Agent]) {
        if let data = try? encoder.encode(agents) {
            defaults.set(data, forKey: "cached_agents")
        }
    }

    func getCachedAgents() -> [Agent] {
        guard let data = defaults.data(forKey: "cached_agents"),
              let agents = try? decoder.decode([Agent].self, from: data) else {
            return []
        }
        return agents
    }

    // MARK: - Projects Cache

    func cacheProjects(_ projects: [Project]) {
        if let data = try? encoder.encode(projects) {
            defaults.set(data, forKey: "cached_projects")
        }
    }

    func getCachedProjects() -> [Project] {
        guard let data = defaults.data(forKey: "cached_projects"),
              let projects = try? decoder.decode([Project].self, from: data) else {
            return []
        }
        return projects
    }

    // MARK: - Chat History (Local agent chats, not project chats)

    func saveChatHistory(agentId: String, messages: [ChatMessage]) {
        if let data = try? encoder.encode(messages) {
            defaults.set(data, forKey: "chat_history_\(agentId)")
        }
    }

    func getChatHistory(agentId: String) -> [ChatMessage] {
        guard let data = defaults.data(forKey: "chat_history_\(agentId)"),
              let messages = try? decoder.decode([ChatMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func clearChatHistory(agentId: String) {
        defaults.removeObject(forKey: "chat_history_\(agentId)")
    }

    // MARK: - Selected Model

    func saveSelectedModel(_ modelId: String) {
        defaults.set(modelId, forKey: "selected_model_id")
    }

    func getSelectedModel() -> String? {
        defaults.string(forKey: "selected_model_id")
    }

    // MARK: - Clear All

    func clearAll() {
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
    }
}
