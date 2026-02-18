import Foundation

struct Agent: Codable, Identifiable, Hashable {
    let id: String
    var userId: String?
    var name: String
    var description: String?
    var systemPrompt: String
    var modelProvider: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var skills: [String]
    var config: [String: AnyCodable]
    var isBuiltin: Bool
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case description
        case systemPrompt = "system_prompt"
        case modelProvider = "model_provider"
        case modelName = "model_name"
        case temperature
        case maxTokens = "max_tokens"
        case skills
        case config
        case isBuiltin = "is_builtin"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func new() -> Agent {
        Agent(
            id: "",
            userId: nil,
            name: "",
            description: nil,
            systemPrompt: "You are a helpful assistant.",
            modelProvider: "mlx",
            modelName: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            temperature: 0.7,
            maxTokens: 4096,
            skills: [],
            config: [:],
            isBuiltin: false
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }
}

struct AgentsResponse: Codable {
    let agents: [Agent]
}

// MARK: - AnyCodable for flexible JSON

struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }

    func hash(into hasher: inout Hasher) {
        if let s = value as? String { hasher.combine(s) }
        else if let i = value as? Int { hasher.combine(i) }
        else if let d = value as? Double { hasher.combine(d) }
        else if let b = value as? Bool { hasher.combine(b) }
        else { hasher.combine(0) }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
