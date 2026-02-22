import SwiftUI

struct ProjectsListView: View {
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var agentsVM: AgentsViewModel
    @State private var showCreateSheet = false
    @State private var newProjectTitle = ""
    @State private var selectedAgentIds: Set<String> = []
    @State private var projectToDelete: Project?

    var body: some View {
        ZStack {
                Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea()

                if projectsVM.projects.isEmpty && !projectsVM.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No projects yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Create a project to start collaborating with agents")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("Create Project", systemImage: "plus")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    List {
                        ForEach(projectsVM.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectListRow(project: project)
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    projectToDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Agent Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            .refreshable {
                await projectsVM.loadProjects()
            }
            .task {
                await projectsVM.loadProjects()
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateProjectSheet(
                    title: $newProjectTitle,
                    selectedAgentIds: $selectedAgentIds,
                    agents: agentsVM.agents
                ) {
                    Task {
                        if let _ = await projectsVM.createProject(
                            title: newProjectTitle,
                            agentIds: Array(selectedAgentIds)
                        ) {
                            newProjectTitle = ""
                            selectedAgentIds.removeAll()
                            showCreateSheet = false
                        }
                    }
                }
            }
        .alert("Delete Project", isPresented: .init(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { projectToDelete = nil }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    Task { await projectsVM.deleteProject(project) }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(projectToDelete?.title ?? "")\"?")
        }
    }
}

// MARK: - Project List Row

struct ProjectListRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.fill")
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Label("\(project.agents.count)", systemImage: "person.2")
                    Label("\(project.messageCount ?? 0)", systemImage: "bubble.left")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()

            StatusBadge(status: project.status)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Project Sheet

struct CreateProjectSheet: View {
    @Binding var title: String
    @Binding var selectedAgentIds: Set<String>
    let agents: [Agent]
    let onCreate: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Name") {
                    TextField("Enter project name", text: $title)
                        .foregroundColor(.white)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("Assign Agents") {
                    if agents.isEmpty {
                        Text("No agents available. Create agents first.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(agents) { agent in
                            Button {
                                if selectedAgentIds.contains(agent.id) {
                                    selectedAgentIds.remove(agent.id)
                                } else {
                                    selectedAgentIds.insert(agent.id)
                                }
                            } label: {
                                HStack {
                                    Text(agent.name)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if selectedAgentIds.contains(agent.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.orange)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { onCreate() }
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .disabled(title.isEmpty)
                }
            }
        }
    }
}
