import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var selectedAgent: Agent?

    private let api = APIService.shared
    private let mlx = MLXService.shared
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

        // Route: on-device MLX if agent uses mlx provider AND model is loaded,
        // otherwise fall through to backend API.
        let useOnDevice = agent.modelProvider == "mlx" && mlx.isModelLoaded

        let placeholder = ChatMessage.assistantMessage(
            useOnDevice ? "" : "...",
            agentId: agent.id,
            agentName: agent.name
        )
        messages.append(placeholder)

        if useOnDevice {
            await sendViaMLX(agent: agent, content: content)
        } else {
            await sendViaBackend(agent: agent, content: content)
        }

        isGenerating = false
    }

    // MARK: - On-device MLX (streaming)

    private func sendViaMLX(agent: Agent, content: String) async {
        let history = messages.dropLast(2).map { (role: $0.role, content: $0.content) }

        do {
            try await mlx.generateStreaming(
                systemPrompt: agent.systemPrompt,
                conversationHistory: Array(history),
                userMessage: content,
                temperature: agent.temperature,
                maxTokens: agent.maxTokens
            ) { [weak self] fullText in
                guard let self else { return }
                if let lastIndex = self.messages.indices.last {
                    self.messages[lastIndex] = ChatMessage.assistantMessage(
                        fullText,
                        agentId: agent.id,
                        agentName: agent.name
                    )
                }
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
    }

    // MARK: - Backend API (cloud)

    private func sendViaBackend(agent: Agent, content: String) async {
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
