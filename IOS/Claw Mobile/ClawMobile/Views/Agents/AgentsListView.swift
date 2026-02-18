import SwiftUI

struct AgentsListView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @State private var showCreateSheet = false
    @State private var agentToDelete: Agent?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea()

                if agentsVM.agents.isEmpty && !agentsVM.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No agents yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Create an agent to get started")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("Create Agent", systemImage: "plus")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                } else {
                    List {
                        ForEach(agentsVM.agents) { agent in
                            NavigationLink {
                                AgentDetailView(agent: agent)
                                    .environmentObject(agentsVM)
                            } label: {
                                AgentListRow(agent: agent)
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                            .swipeActions(edge: .trailing) {
                                if !agent.isBuiltin {
                                    Button(role: .destructive) {
                                        agentToDelete = agent
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Agents")
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
                await agentsVM.loadAgents()
            }
            .sheet(isPresented: $showCreateSheet) {
                AgentDetailView(agent: Agent.new(), isNew: true)
                    .environmentObject(agentsVM)
            }
            .alert("Delete Agent", isPresented: .init(
                get: { agentToDelete != nil },
                set: { if !$0 { agentToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { agentToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let agent = agentToDelete {
                        Task { await agentsVM.deleteAgent(agent) }
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(agentToDelete?.name ?? "")\"?")
            }
            .overlay {
                if let error = agentsVM.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            .padding()
                            .onTapGesture {
                                agentsVM.errorMessage = nil
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Agent List Row

struct AgentListRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Text(String(agent.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(agent.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    if agent.isBuiltin {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                if let desc = agent.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Text(agent.modelName)
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
