import SwiftUI

struct AgentDetailView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @Environment(\.dismiss) var dismiss

    @State var agent: Agent
    var isNew: Bool = false

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Basic Info Section
                    sectionCard(title: "Basic Info") {
                        VStack(spacing: 12) {
                            TextField("Agent Name", text: $agent.name)
                                .textFieldStyle(DarkTextFieldStyle())

                            TextField("Description (optional)", text: Binding(
                                get: { agent.description ?? "" },
                                set: { agent.description = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(DarkTextFieldStyle())
                        }
                    }

                    // System Prompt Section
                    sectionCard(title: "System Prompt") {
                        TextEditor(text: $agent.systemPrompt)
                            .frame(minHeight: 120)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                    }

                    // Model Section
                    sectionCard(title: "Model Settings") {
                        VStack(spacing: 16) {
                            // Model Picker
                            HStack {
                                Text("Model")
                                    .foregroundColor(.white)
                                Spacer()
                                Picker("", selection: $agent.modelName) {
                                    ForEach(MLXModelInfo.defaultModels) { model in
                                        Text(model.name)
                                            .tag(model.huggingFaceRepo)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.orange)
                            }

                            Divider().background(Color.white.opacity(0.1))

                            // Temperature - Custom slider with better touch
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Temperature")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(String(format: "%.1f", agent.temperature))
                                        .foregroundColor(.orange)
                                        .fontWeight(.semibold)
                                }

                                // Custom temperature buttons for reliable interaction
                                HStack(spacing: 12) {
                                    temperatureButton(value: 0.0, label: "0")
                                    temperatureButton(value: 0.5, label: "0.5")
                                    temperatureButton(value: 0.7, label: "0.7")
                                    temperatureButton(value: 1.0, label: "1.0")
                                    temperatureButton(value: 1.5, label: "1.5")
                                    temperatureButton(value: 2.0, label: "2.0")
                                }
                            }

                            Divider().background(Color.white.opacity(0.1))

                            // Max Tokens - Custom buttons for reliable interaction
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Max Tokens")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(agent.maxTokens)")
                                        .foregroundColor(.orange)
                                        .fontWeight(.semibold)
                                }

                                HStack(spacing: 12) {
                                    // Decrease button
                                    Button {
                                        if agent.maxTokens > 256 {
                                            agent.maxTokens -= 256
                                        }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title2.bold())
                                            .foregroundColor(.white)
                                            .frame(width: 50, height: 44)
                                            .background(Color.white.opacity(0.15))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)

                                    // Preset buttons
                                    tokensButton(value: 1024)
                                    tokensButton(value: 2048)
                                    tokensButton(value: 4096)
                                    tokensButton(value: 8192)

                                    // Increase button
                                    Button {
                                        if agent.maxTokens < 8192 {
                                            agent.maxTokens += 256
                                        }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title2.bold())
                                            .foregroundColor(.white)
                                            .frame(width: 50, height: 44)
                                            .background(Color.white.opacity(0.15))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Save Button - Large, prominent, always visible
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        Task { await saveAgent() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(isSaving ? "Saving..." : "Save Agent")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(agent.name.isEmpty || isSaving ? Color.gray : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.name.isEmpty || isSaving)
                    .padding(.top, 8)

                    // Delete button for existing agents
                    if !isNew && !agent.isBuiltin {
                        Button {
                            Task {
                                if await agentsVM.deleteAgent(agent) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Agent")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle(isNew ? "New Agent" : agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.gray)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if let error = agentsVM.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
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

    // MARK: - Helper Views

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.gray)

            content()
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private func temperatureButton(value: Double, label: String) -> some View {
        Button {
            agent.temperature = value
        } label: {
            Text(label)
                .font(.subheadline.bold())
                .foregroundColor(abs(agent.temperature - value) < 0.05 ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(abs(agent.temperature - value) < 0.05 ? Color.orange : Color.white.opacity(0.15))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func tokensButton(value: Int) -> some View {
        Button {
            agent.maxTokens = value
        } label: {
            Text("\(value / 1000)K")
                .font(.subheadline.bold())
                .foregroundColor(agent.maxTokens == value ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(agent.maxTokens == value ? Color.orange : Color.white.opacity(0.15))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func saveAgent() async {
        isSaving = true
        agent.modelProvider = "mlx"

        if isNew {
            if await agentsVM.createAgent(agent) {
                dismiss()
            }
        } else {
            if await agentsVM.updateAgent(agent) {
                dismiss()
            }
        }
        isSaving = false
    }
}

// MARK: - Custom TextField Style

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .foregroundColor(.white)
    }
}
