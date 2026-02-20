import Foundation

@MainActor
class APIService {
    static let shared = APIService()

    // TODO: Update this to your Railway backend URL
    private let baseURL = "https://claw-staffer-production.up.railway.app/api"

    private init() {}

    private var authToken: String? {
        AuthService.shared.backendToken
    }

    // MARK: - Firebase Token Exchange

    func exchangeFirebaseToken(idToken: String) async throws -> AuthTokenResponse {
        let url = URL(string: "\(baseURL)/auth/firebase")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["idToken": idToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            // Log error details for debugging
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[APIService] Firebase auth failed (\(httpResponse.statusCode)): \(errorBody)")
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(AuthTokenResponse.self, from: data)
    }

    // MARK: - Agents

    func fetchAgents() async throws -> [Agent] {
        let data = try await get("/agents")
        let response = try JSONDecoder().decode(AgentsResponse.self, from: data)
        return response.agents
    }

    func createAgent(_ agent: Agent) async throws -> Agent {
        let body: [String: Any] = [
            "name": agent.name,
            "description": agent.description ?? "",
            "systemPrompt": agent.systemPrompt,
            "modelProvider": agent.modelProvider,
            "modelName": agent.modelName,
            "temperature": agent.temperature,
            "maxTokens": agent.maxTokens,
            "skills": agent.skills,
        ]
        print("[APIService] Creating agent: \(body)")
        let data = try await post("/agents", body: body)
        print("[APIService] Create agent response: \(String(data: data, encoding: .utf8) ?? "nil")")
        do {
            return try JSONDecoder().decode(Agent.self, from: data)
        } catch {
            print("[APIService] Failed to decode agent: \(error)")
            throw APIError.decodingError
        }
    }

    func updateAgent(id: String, updates: [String: Any]) async throws -> Agent {
        let data = try await patch("/agents/\(id)", body: updates)
        return try JSONDecoder().decode(Agent.self, from: data)
    }

    func deleteAgent(id: String) async throws {
        _ = try await delete("/agents/\(id)")
    }

    // MARK: - Projects

    func fetchProjects() async throws -> [Project] {
        let data = try await get("/projects")
        let response = try JSONDecoder().decode(ProjectsResponse.self, from: data)
        return response.projects
    }

    func fetchProject(id: String) async throws -> Project {
        let data = try await get("/projects/\(id)")
        return try JSONDecoder().decode(Project.self, from: data)
    }

    func createProject(title: String, agentIds: [String] = []) async throws -> Project {
        let body: [String: Any] = [
            "title": title,
            "agentIds": agentIds,
        ]
        let data = try await post("/projects", body: body)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    func updateProject(id: String, updates: [String: Any]) async throws -> Project {
        let data = try await patch("/projects/\(id)", body: updates)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    func deleteProject(id: String) async throws {
        _ = try await delete("/projects/\(id)")
    }

    func addAgentToProject(projectId: String, agentId: String) async throws {
        _ = try await post("/projects/\(projectId)/agents", body: ["agentId": agentId])
    }

    func removeAgentFromProject(projectId: String, agentId: String) async throws {
        _ = try await delete("/projects/\(projectId)/agents/\(agentId)")
    }

    func sendProjectMessage(projectId: String, content: String, targetAgentId: String? = nil, mentions: [String]? = nil) async throws -> SendMessageResponse {
        var body: [String: Any] = ["content": content]
        if let targetAgentId = targetAgentId {
            body["targetAgentId"] = targetAgentId
        }
        if let mentions = mentions {
            body["mentions"] = mentions
        }
        let data = try await post("/projects/\(projectId)/messages", body: body)
        return try JSONDecoder().decode(SendMessageResponse.self, from: data)
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String) async throws -> Data {
        var request = makeRequest(path: path, method: "GET")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, path: path)
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = makeRequest(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, path: path)
        return data
    }

    private func patch(_ path: String, body: [String: Any]) async throws -> Data {
        var request = makeRequest(path: path, method: "PATCH")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, path: path)
        return data
    }

    private func delete(_ path: String) async throws -> Data {
        let request = makeRequest(path: path, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, path: path)
        return data
    }

    private var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private func makeRequest(path: String, method: String) -> URLRequest {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data, path: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to extract error message from response
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[APIService] \(path) failed (\(httpResponse.statusCode)): \(errorBody)")
                // Try to parse JSON error
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String {
                    throw APIError.serverError(message: errorMessage)
                }
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case authFailed
    case invalidResponse
    case httpError(statusCode: Int)
    case serverError(message: String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .authFailed: return "Authentication failed"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "Server error (HTTP \(code))"
        case .serverError(let message): return message
        case .decodingError: return "Failed to parse server response"
        }
    }
}
