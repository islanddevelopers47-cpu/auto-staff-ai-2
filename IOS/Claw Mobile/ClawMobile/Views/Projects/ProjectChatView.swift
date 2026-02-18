import SwiftUI

struct ProjectChatView: View {
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var agentsVM: AgentsViewModel

    let projectId: String
    @State private var messageText = ""
    @State private var selectedAgentId: String?
    @State private var showAgentSidebar = false
    @State private var showAddAgent = false
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            // Main chat area
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if let project = projectsVM.currentProject {
                                ForEach(project.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }

                            if projectsVM.isSending {
                                HStack {
                                    ProgressView()
                                        .tint(.orange)
                                    Text("Agent is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: projectsVM.currentProject?.messages.count) { _, _ in
                        withAnimation {
                            if let lastMsg = projectsVM.currentProject?.messages.last {
                                proxy.scrollTo(lastMsg.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Input bar
                HStack(spacing: 12) {
                    if let agentName = selectedAgentName {
                        HStack(spacing: 4) {
                            Text("@\(agentName)")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Button {
                                selectedAgentId = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                    }

                    TextField("Message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .lineLimit(1...5)

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(messageText.isEmpty ? .gray : .orange)
                    }
                    .disabled(messageText.isEmpty || projectsVM.isSending)
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
            }

            // Agent sidebar (shown on iPad or when toggled)
            if showAgentSidebar {
                Divider().background(Color.white.opacity(0.1))
                AgentSidebarView(
                    project: projectsVM.currentProject,
                    allAgents: agentsVM.agents,
                    selectedAgentId: $selectedAgentId,
                    onAddAgent: { showAddAgent = true },
                    onRemoveAgent: { agentId in
                        Task {
                            await projectsVM.removeAgent(projectId: projectId, agentId: agentId)
                        }
                    }
                )
                .frame(width: 220)
            }
        }
        .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
        .navigationTitle(projectsVM.currentProject?.title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { showAgentSidebar.toggle() }
                    } label: {
                        Image(systemName: "person.2")
                            .foregroundColor(showAgentSidebar ? .orange : .gray)
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .task {
            await projectsVM.loadProject(id: projectId)
        }
        .sheet(isPresented: $showAddAgent) {
            AddAgentToProjectSheet(
                agents: agentsVM.agents,
                projectAgentIds: Set((projectsVM.currentProject?.agents ?? []).map { $0.agentId })
            ) { agentId in
                Task {
                    await projectsVM.addAgent(projectId: projectId, agentId: agentId)
                    showAddAgent = false
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            ProjectSettingsSheet(project: projectsVM.currentProject)
                .environmentObject(projectsVM)
        }
    }

    private var selectedAgentName: String? {
        guard let agentId = selectedAgentId,
              let agent = agentsVM.agents.first(where: { $0.id == agentId }) else {
            return nil
        }
        return agent.name
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        messageText = ""

        Task {
            await projectsVM.sendMessage(content: content, targetAgentId: selectedAgentId)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if !message.isUser, let name = message.agentName {
                    Text(name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                Text(message.content)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        message.isUser
                            ? Color.orange.opacity(0.3)
                            : Color.white.opacity(0.08)
                    )
                    .cornerRadius(16, corners: message.isUser
                        ? [.topLeft, .topRight, .bottomLeft]
                        : [.topLeft, .topRight, .bottomRight]
                    )

                if let time = message.createdAt {
                    Text(formatTime(time))
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer() }
        }
    }

    private func formatTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        return ""
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Agent Sidebar

struct AgentSidebarView: View {
    let project: Project?
    let allAgents: [Agent]
    @Binding var selectedAgentId: String?
    let onAddAgent: () -> Void
    let onRemoveAgent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onAddAgent) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.orange)
                }
            }
            .padding()

            Divider().background(Color.white.opacity(0.1))

            if let agents = project?.agents, !agents.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // "All Agents" option
                        Button {
                            selectedAgentId = nil
                        } label: {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.purple)
                                Text("All Agents")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedAgentId == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(selectedAgentId == nil ? Color.white.opacity(0.08) : Color.clear)
                            .cornerRadius(8)
                        }

                        ForEach(agents) { projectAgent in
                            let agent = allAgents.first(where: { $0.id == projectAgent.agentId })
                            Button {
                                selectedAgentId = projectAgent.agentId
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Text(String((agent?.name ?? projectAgent.name ?? "?").prefix(1)).uppercased())
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        )
                                    Text(agent?.name ?? projectAgent.name ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if selectedAgentId == projectAgent.agentId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(selectedAgentId == projectAgent.agentId ? Color.white.opacity(0.08) : Color.clear)
                                .cornerRadius(8)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onRemoveAgent(projectAgent.agentId)
                                } label: {
                                    Label("Remove from Project", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No agents assigned")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Button("Add Agent", action: onAddAgent)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white.opacity(0.03))
    }
}

// MARK: - Add Agent Sheet

struct AddAgentToProjectSheet: View {
    let agents: [Agent]
    let projectAgentIds: Set<String>
    let onAdd: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var availableAgents: [Agent] {
        agents.filter { !projectAgentIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableAgents.isEmpty {
                    Text("All agents are already in this project")
                        .foregroundColor(.gray)
                } else {
                    ForEach(availableAgents) { agent in
                        Button {
                            onAdd(agent.id)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(String(agent.name.prefix(1)).uppercased())
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                                VStack(alignment: .leading) {
                                    Text(agent.name)
                                        .foregroundColor(.white)
                                    if let desc = agent.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.orange)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Add Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Project Settings Sheet

struct ProjectSettingsSheet: View {
    let project: Project?
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Name") {
                    TextField("Title", text: $title)
                        .foregroundColor(.white)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("Status") {
                    if let project = project {
                        HStack {
                            Text("Current Status")
                            Spacer()
                            StatusBadge(status: project.status)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("Info") {
                    if let project = project {
                        HStack {
                            Text("Agents")
                            Spacer()
                            Text("\(project.agents.count)")
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Messages")
                            Spacer()
                            Text("\(project.messages.count)")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Project Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let project = project, !title.isEmpty else { return }
                        Task {
                            _ = try? await APIService.shared.updateProject(
                                id: project.id,
                                updates: ["title": title]
                            )
                            await projectsVM.loadProject(id: project.id)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
            .onAppear {
                title = project?.title ?? ""
            }
        }
    }
}
