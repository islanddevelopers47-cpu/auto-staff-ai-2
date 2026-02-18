import Foundation

struct ChatMessage: Codable, Identifiable {
    let id: String
    var projectId: String?
    var agentId: String?
    var agentName: String?
    var role: String // "user" or "assistant"
    var content: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case role
        case content
        case createdAt = "created_at"
    }

    var isUser: Bool { role == "user" }

    static func userMessage(_ content: String, projectId: String? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            projectId: projectId,
            agentId: nil,
            agentName: nil,
            role: "user",
            content: content,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func assistantMessage(_ content: String, agentId: String? = nil, agentName: String? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            projectId: nil,
            agentId: agentId,
            agentName: agentName,
            role: "assistant",
            content: content,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
