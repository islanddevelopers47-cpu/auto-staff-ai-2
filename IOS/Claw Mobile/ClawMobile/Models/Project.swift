import Foundation

struct Project: Codable, Identifiable {
    let id: String
    var userId: String?
    var title: String
    var status: String
    var integrations: [String]
    var agents: [ProjectAgent]
    var messages: [ChatMessage]
    var messageCount: Int?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case status
        case integrations
        case agents
        case messages
        case messageCount = "message_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        integrations = try container.decodeIfPresent([String].self, forKey: .integrations) ?? []
        agents = try container.decodeIfPresent([ProjectAgent].self, forKey: .agents) ?? []
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    init(id: String, title: String, status: String = "active", agents: [ProjectAgent] = [], messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.status = status
        self.integrations = []
        self.agents = agents
        self.messages = messages
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(integrations, forKey: .integrations)
        try container.encode(agents, forKey: .agents)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct ProjectAgent: Codable, Identifiable {
    let id: String
    var agentId: String
    var name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case name
    }
}

struct ProjectsResponse: Codable {
    let projects: [Project]
}

struct SendMessageResponse: Codable {
    let userMessage: ChatMessage
    let messages: [ChatMessage]
}
