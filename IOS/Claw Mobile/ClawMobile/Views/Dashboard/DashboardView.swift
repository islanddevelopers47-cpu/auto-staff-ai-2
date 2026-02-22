import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                    // Stats cards
                    HStack(spacing: 16) {
                        StatCard(
                            title: "Agents",
                            value: "\(dashboardVM.agentCount)",
                            icon: "person.2.fill",
                            color: .orange
                        )
                        StatCard(
                            title: "Projects",
                            value: "\(dashboardVM.projectCount)",
                            icon: "folder.fill",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // MLX Status
                    MLXStatusCard()

                    // Recent Projects
                    if !dashboardVM.recentProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Projects")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            ForEach(dashboardVM.recentProjects) { project in
                                ProjectRow(project: project)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.top)
            }
        }
        .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await dashboardVM.loadDashboard()
        }
        .task {
            await dashboardVM.loadDashboard()
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
}

// MARK: - MLX Status Card

struct MLXStatusCard: View {
    @ObservedObject var mlxService = MLXService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.green)
                Text("On-Device AI")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Circle()
                    .fill(mlxService.isModelLoaded ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(mlxService.isModelLoaded ? "Ready" : "No Model")
                    .font(.caption)
                    .foregroundColor(mlxService.isModelLoaded ? .green : .red)
            }

            if let modelId = mlxService.currentModelId,
               let model = MLXModelInfo.defaultModels.first(where: { $0.id == modelId }) {
                Text(model.name)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                Text("Go to Settings to download and load a model")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Label("\(project.agents.count) agents", systemImage: "person.2")
                    Label("\(project.messageCount ?? 0) messages", systemImage: "bubble.left")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            Spacer()
            StatusBadge(status: project.status)
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    var color: Color {
        switch status {
        case "active": return .green
        case "completed": return .blue
        case "archived": return .gray
        default: return .orange
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}
