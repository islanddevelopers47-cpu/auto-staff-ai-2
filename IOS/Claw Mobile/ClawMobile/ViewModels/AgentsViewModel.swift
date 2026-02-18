import Foundation

@MainActor
class AgentsViewModel: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        // Load cached agents first
        agents = StorageService.shared.getCachedAgents()
    }

    func loadAgents() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await APIService.shared.fetchAgents()
            agents = fetched
            StorageService.shared.cacheAgents(fetched)
        } catch {
            errorMessage = error.localizedDescription
            // Fall back to cached
            if agents.isEmpty {
                agents = StorageService.shared.getCachedAgents()
            }
        }

        isLoading = false
    }

    func createAgent(_ agent: Agent) async -> Bool {
        // Check unique name
        if agents.contains(where: { $0.name.lowercased() == agent.name.lowercased() }) {
            errorMessage = "An agent with this name already exists. Please choose a unique name."
            return false
        }

        do {
            let created = try await APIService.shared.createAgent(agent)
            agents.append(created)
            StorageService.shared.cacheAgents(agents)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAgent(_ agent: Agent) async -> Bool {
        // Check unique name (excluding self)
        if agents.contains(where: { $0.id != agent.id && $0.name.lowercased() == agent.name.lowercased() }) {
            errorMessage = "An agent with this name already exists. Please choose a unique name."
            return false
        }

        do {
            let updates: [String: Any] = [
                "name": agent.name,
                "description": agent.description ?? "",
                "systemPrompt": agent.systemPrompt,
                "modelProvider": agent.modelProvider,
                "modelName": agent.modelName,
                "temperature": agent.temperature,
                "maxTokens": agent.maxTokens,
            ]
            let updated = try await APIService.shared.updateAgent(id: agent.id, updates: updates)
            if let index = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[index] = updated
            }
            StorageService.shared.cacheAgents(agents)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAgent(_ agent: Agent) async -> Bool {
        do {
            try await APIService.shared.deleteAgent(id: agent.id)
            agents.removeAll { $0.id == agent.id }
            StorageService.shared.cacheAgents(agents)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
