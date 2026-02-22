import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var agentsVM: AgentsViewModel
    @State private var messageText = ""
    @State private var showAgentPicker = false
    private let bgColor = Color(red: 0.08, green: 0.04, blue: 0.12)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            VStack(spacing: 0) {
                // Agent selector bar
                if let agent = chatVM.selectedAgent {
                    HStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(String(agent.name.prefix(1)).uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(MLXService.shared.isModelLoaded ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(MLXService.shared.isModelLoaded ? "On-device MLX" : "No model loaded")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Button {
                            showAgentPicker = true
                        } label: {
                            Text("Switch")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Button {
                            chatVM.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                } else {
                    // No agent selected - fill remaining space
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Select an agent to start chatting")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Chat runs entirely on-device using MLX")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                        Button {
                            showAgentPicker = true
                        } label: {
                            Label("Choose Agent", systemImage: "person.crop.circle.badge.plus")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    Spacer()
                }

                if chatVM.selectedAgent != nil {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(chatVM.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }

                                if chatVM.isGenerating {
                                    HStack {
                                        ProgressView()
                                            .tint(.orange)
                                            .scaleEffect(0.8)
                                        Text("Generating...")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .id("generating")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: chatVM.messages.count) { _, _ in
                            withAnimation {
                                if let lastMsg = chatVM.messages.last {
                                    proxy.scrollTo(lastMsg.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Input bar
                    HStack(spacing: 12) {
                        TextField("Message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .lineLimit(1...5)

                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(messageText.isEmpty || chatVM.isGenerating ? .gray : .orange)
                        }
                        .disabled(messageText.isEmpty || chatVM.isGenerating)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                }
            }
            .background(bgColor.ignoresSafeArea())
            .navigationTitle("Chat")
            .toolbarBackground(bgColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAgentPicker) {
                AgentPickerSheet(agents: agentsVM.agents) { agent in
                    chatVM.selectAgent(agent)
                    showAgentPicker = false
                }
            }
            .overlay {
                if let error = chatVM.errorMessage {
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
                                chatVM.errorMessage = nil
                            }
                    }
                }
            }
        }
        .background(bgColor.ignoresSafeArea())
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        messageText = ""
        Task {
            await chatVM.sendMessage(content)
        }
    }
}

// MARK: - Agent Picker Sheet

struct AgentPickerSheet: View {
    let agents: [Agent]
    let onSelect: (Agent) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(agents) { agent in
                    Button {
                        onSelect(agent)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(agent.name.prefix(1)).uppercased())
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                if let desc = agent.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Choose Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
