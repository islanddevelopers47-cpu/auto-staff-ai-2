import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var agentsVM = AgentsViewModel()
    @StateObject private var projectsVM = ProjectsViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var dashboardVM = DashboardViewModel()

    var body: some View {
        TabView {
            DashboardView()
                .environmentObject(dashboardVM)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

            AgentsListView()
                .environmentObject(agentsVM)
                .tabItem {
                    Label("Agents", systemImage: "person.2")
                }

            ProjectsListView()
                .environmentObject(projectsVM)
                .environmentObject(agentsVM)
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }

            ChatView()
                .environmentObject(chatVM)
                .environmentObject(agentsVM)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.orange)
        .task {
            await agentsVM.loadAgents()
        }
    }
}
