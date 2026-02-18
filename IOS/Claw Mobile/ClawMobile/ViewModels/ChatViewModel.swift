import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var selectedAgent: Agent?
    @Published var streamingText = ""

    private let mlxService = MLXService.shared
    private let storageService = StorageService.shared

    func selectAgent(_ agent: Agent) {
        selectedAgent = agent
        messages = storageService.getChatHistory(agentId: agent.id)
    }

    func sendMessage(_ content: String) async {
        guard let agent = selectedAgent else {
            errorMessage = "Please select an agent first"
            return
        }

        guard mlxService.isModelLoaded else {
            errorMessage = "No model loaded. Go to Settings to download and load a model."
            return
        }

        // Add user message
        let userMsg = ChatMessage.userMessage(content)
        messages.append(userMsg)
        saveChatHistory()

        isGenerating = true
        streamingText = ""
        errorMessage = nil

        // Add placeholder assistant message
        let assistantMsg = ChatMessage.assistantMessage("", agentId: agent.id, agentName: agent.name)
        messages.append(assistantMsg)

        do {
            let history = messages.dropLast(2).map { (role: $0.role, content: $0.content) }

            try await mlxService.generateStreaming(
                systemPrompt: agent.systemPrompt,
                conversationHistory: Array(history),
                userMessage: content,
                temperature: agent.temperature,
                maxTokens: agent.maxTokens
            ) { [weak self] token in
                guard let self = self else { return }
                Task { @MainActor in
                    self.streamingText += token
                    if let lastIndex = self.messages.indices.last {
                        self.messages[lastIndex] = ChatMessage.assistantMessage(
                            self.streamingText,
                            agentId: agent.id,
                            agentName: agent.name
                        )
                    }
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

        isGenerating = false
        streamingText = ""
    }

    func clearHistory() {
        messages.removeAll()
        if let agent = selectedAgent {
            storageService.clearChatHistory(agentId: agent.id)
        }
    }

    private func saveChatHistory() {
        guard let agent = selectedAgent else { return }
        storageService.saveChatHistory(agentId: agent.id, messages: messages)
    }
}
