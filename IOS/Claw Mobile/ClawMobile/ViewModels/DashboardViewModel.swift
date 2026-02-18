import Foundation

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var agentCount = 0
    @Published var projectCount = 0
    @Published var recentProjects: [Project] = []
    @Published var isLoading = false

    func loadDashboard() async {
        isLoading = true

        do {
            let agents = try await APIService.shared.fetchAgents()
            agentCount = agents.count

            let projects = try await APIService.shared.fetchProjects()
            projectCount = projects.count
            recentProjects = Array(projects.prefix(5))
        } catch {
            // Use cached data
            agentCount = StorageService.shared.getCachedAgents().count
            let cached = StorageService.shared.getCachedProjects()
            projectCount = cached.count
            recentProjects = Array(cached.prefix(5))
        }

        isLoading = false
    }
}
