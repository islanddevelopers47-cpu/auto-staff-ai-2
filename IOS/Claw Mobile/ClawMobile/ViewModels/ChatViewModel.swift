import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var selectedAgent: Agent?

    private let api = APIService.shared
    private let storageService = StorageService.shared
    private var sessionId: String?

    func selectAgent(_ agent: Agent) {
        selectedAgent = agent
        sessionId = nil
        messages = storageService.getChatHistory(agentId: agent.id)
    }

    func sendMessage(_ content: String) async {
        guard let agent = selectedAgent else {
            errorMessage = "Please select an agent first"
            return
        }

        guard !agent.id.isEmpty else {
            errorMessage = "Agent not saved yet"
            return
        }

        let userMsg = ChatMessage.userMessage(content)
        messages.append(userMsg)
        saveChatHistory()

        isGenerating = true
        errorMessage = nil

        let placeholder = ChatMessage.assistantMessage("...", agentId: agent.id, agentName: agent.name)
        messages.append(placeholder)

        do {
            await AuthService.shared.refreshTokenIfNeeded()
            let result = try await api.chat(
                agentId: agent.id,
                message: content,
                sessionId: sessionId
            )
            sessionId = result.sessionId
            if let lastIndex = messages.indices.last {
                messages[lastIndex] = ChatMessage.assistantMessage(
                    result.response,
                    agentId: agent.id,
                    agentName: agent.name
                )
            }
            saveChatHistory()
        } catch {
            errorMessage = error.localizedDescription
            if let lastIndex = messages.indices.last {
                messages[lastIndex] = ChatMessage.assistantMessage(
                    "[Error: \(error.localizedDescription)]",
                    agentId: agent.id,
                    agentName: agent.name
                )
            }
        }

        isGenerating = false
    }

    func clearHistory() {
        messages.removeAll()
        sessionId = nil
        if let agent = selectedAgent {
            storageService.clearChatHistory(agentId: agent.id)
        }
    }

    private func saveChatHistory() {
        guard let agent = selectedAgent else { return }
        storageService.saveChatHistory(agentId: agent.id, messages: messages)
    }
}
