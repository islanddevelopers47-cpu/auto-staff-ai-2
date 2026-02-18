import SwiftUI

struct AgentDetailView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @Environment(\.dismiss) var dismiss

    @State var agent: Agent
    var isNew: Bool = false

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Agent Name", text: $agent.name)
                        .foregroundColor(.white)

                    TextField("Description (optional)", text: Binding(
                        get: { agent.description ?? "" },
                        set: { agent.description = $0.isEmpty ? nil : $0 }
                    ))
                    .foregroundColor(.white)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("System Prompt") {
                    TextEditor(text: $agent.systemPrompt)
                        .frame(minHeight: 120)
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("Model") {
                    Picker("Model", selection: $agent.modelName) {
                        ForEach(MLXModelInfo.defaultModels) { model in
                            Text(model.name)
                                .tag(model.huggingFaceRepo)
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundColor(.white)

                    HStack {
                        Text("Temperature")
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.1f", agent.temperature))
                            .foregroundColor(.orange)
                    }
                    Slider(value: $agent.temperature, in: 0...2, step: 0.1)
                        .tint(.orange)

                    HStack {
                        Text("Max Tokens")
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(agent.maxTokens)")
                            .foregroundColor(.orange)
                    }
                    Stepper("", value: $agent.maxTokens, in: 256...8192, step: 256)
                        .labelsHidden()
                }
                .listRowBackground(Color.white.opacity(0.06))

                if !isNew && !agent.isBuiltin {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                if await agentsVM.deleteAgent(agent) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Agent", systemImage: "trash")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }
                    .listRowBackground(Color.red.opacity(0.1))
                }
            }
            .scrollContentBackground(.hidden)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveAgent() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.orange)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                    .disabled(agent.name.isEmpty || isSaving)
                }
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
