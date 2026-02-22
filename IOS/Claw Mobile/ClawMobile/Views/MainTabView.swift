import SwiftUI

private let bgColor = Color(red: 0.08, green: 0.04, blue: 0.12)

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var agentsVM = AgentsViewModel()
    @StateObject private var projectsVM = ProjectsViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var dashboardVM = DashboardViewModel()
    @State private var selectedTab = 0

    private struct TabItem {
        let icon: String
        let label: String
    }
    private let tabs: [TabItem] = [
        TabItem(icon: "square.grid.2x2", label: "Dashboard"),
        TabItem(icon: "person.2",        label: "Agents"),
        TabItem(icon: "folder",          label: "Projects"),
        TabItem(icon: "bubble.left.and.bubble.right", label: "Chat"),
        TabItem(icon: "gearshape",       label: "Settings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            bgColor.ignoresSafeArea()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    DashboardView()
                        .environmentObject(dashboardVM)
                case 1:
                    AgentsListView()
                        .environmentObject(agentsVM)
                case 2:
                    ProjectsListView()
                        .environmentObject(projectsVM)
                        .environmentObject(agentsVM)
                case 3:
                    ChatView()
                        .environmentObject(chatVM)
                        .environmentObject(agentsVM)
                default:
                    SettingsView()
                        .environmentObject(authViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bgColor)

            // Custom tab bar
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.12))
                HStack(spacing: 0) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        let tab = tabs[index]
                        Button {
                            selectedTab = index
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 20))
                                Text(tab.label)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(selectedTab == index ? .orange : Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(bgColor)
                // Cover home indicator area
                Rectangle()
                    .fill(bgColor)
                    .frame(height: 0)
            }
            .background(bgColor.ignoresSafeArea(edges: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            await agentsVM.loadAgents()
        }
    }
}
