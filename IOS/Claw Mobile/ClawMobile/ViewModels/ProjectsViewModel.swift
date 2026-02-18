import Foundation

@MainActor
class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var currentProject: Project?
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?

    init() {
        projects = StorageService.shared.getCachedProjects()
    }

    func loadProjects() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await APIService.shared.fetchProjects()
            projects = fetched
            StorageService.shared.cacheProjects(fetched)
        } catch {
            errorMessage = error.localizedDescription
            if projects.isEmpty {
                projects = StorageService.shared.getCachedProjects()
            }
        }

        isLoading = false
    }

    func loadProject(id: String) async {
        isLoading = true
        do {
            let project = try await APIService.shared.fetchProject(id: id)
            currentProject = project
            // Update in list too
            if let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index] = project
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createProject(title: String, agentIds: [String] = []) async -> Project? {
        do {
            let project = try await APIService.shared.createProject(title: title, agentIds: agentIds)
            projects.insert(project, at: 0)
            StorageService.shared.cacheProjects(projects)
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteProject(_ project: Project) async -> Bool {
        do {
            try await APIService.shared.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            if currentProject?.id == project.id {
                currentProject = nil
            }
            StorageService.shared.cacheProjects(projects)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addAgent(projectId: String, agentId: String) async {
        do {
            try await APIService.shared.addAgentToProject(projectId: projectId, agentId: agentId)
            await loadProject(id: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAgent(projectId: String, agentId: String) async {
        do {
            try await APIService.shared.removeAgentFromProject(projectId: projectId, agentId: agentId)
            await loadProject(id: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(content: String, targetAgentId: String? = nil) async {
        guard let project = currentProject else { return }

        isSending = true

        // Parse @mentions from content
        let mentionPattern = /@(\w+)/
        var mentions: [String] = []
        if let regex = try? NSRegularExpression(pattern: "@(\\w+)", options: []) {
            let nsContent = content as NSString
            let results = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            mentions = results.map { nsContent.substring(with: $0.range(at: 1)) }
        }

        // Add user message to UI immediately
        let userMsg = ChatMessage.userMessage(content, projectId: project.id)
        currentProject?.messages.append(userMsg)

        do {
            let response = try await APIService.shared.sendProjectMessage(
                projectId: project.id,
                content: content,
                targetAgentId: targetAgentId,
                mentions: mentions.isEmpty ? nil : mentions
            )

            // Replace optimistic user message and add agent responses
            if let lastIndex = currentProject?.messages.lastIndex(where: { $0.id == userMsg.id }) {
                currentProject?.messages[lastIndex] = response.userMessage
            }
            currentProject?.messages.append(contentsOf: response.messages)
        } catch {
            errorMessage = error.localizedDescription
            // Add error message
            let errorMsg = ChatMessage.assistantMessage("[Error: \(error.localizedDescription)]")
            currentProject?.messages.append(errorMsg)
        }

        isSending = false
    }
}
