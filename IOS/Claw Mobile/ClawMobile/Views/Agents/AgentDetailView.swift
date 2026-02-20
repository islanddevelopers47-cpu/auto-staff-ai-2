import SwiftUI

struct AgentDetailView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @Environment(\.dismiss) var dismiss

    @State var agent: Agent
    var isNew: Bool = false

    @State private var isSaving = false
    @State private var saveError: String?

    private let bgColor = Color(red: 0.08, green: 0.04, blue: 0.12)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                bgColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {

                        // ── STICKY NAME HEADER ──────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Agent Name *")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("Enter a name to enable Save", text: $agent.name)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)
                                .submitLabel(.done)

                            if agent.name.isEmpty {
                                Text("Name is required to save")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                        // ── DESCRIPTION ─────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description (optional)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("Short description", text: Binding(
                                get: { agent.description ?? "" },
                                set: { agent.description = $0.isEmpty ? nil : $0 }
                            ))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                        // ── SYSTEM PROMPT ────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("System Prompt")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextEditor(text: $agent.systemPrompt)
                                .frame(height: 110)
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                        // ── MODEL ────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model")
                                .font(.caption)
                                .foregroundColor(.gray)

                            ForEach(MLXModelInfo.defaultModels) { model in
                                Button {
                                    agent.modelName = model.huggingFaceRepo
                                } label: {
                                    HStack {
                                        Text(model.name)
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                        Spacer()
                                        if agent.modelName == model.huggingFaceRepo {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(12)
                                    .background(agent.modelName == model.huggingFaceRepo
                                        ? Color.orange.opacity(0.15)
                                        : Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                        // ── TEMPERATURE ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Temperature")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%.1f", agent.temperature))
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                            }
                            HStack(spacing: 8) {
                                ForEach([0.0, 0.5, 0.7, 1.0, 1.5, 2.0], id: \.self) { val in
                                    Button {
                                        agent.temperature = val
                                    } label: {
                                        Text(val == 0 ? "0" : String(format: "%.1f", val))
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(abs(agent.temperature - val) < 0.01
                                                ? Color.orange : Color.white.opacity(0.1))
                                            .foregroundColor(abs(agent.temperature - val) < 0.01
                                                ? .black : .white)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                        // ── MAX TOKENS ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Max Tokens")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(agent.maxTokens)")
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                            }
                            HStack(spacing: 8) {
                                Button {
                                    if agent.maxTokens > 256 { agent.maxTokens -= 256 }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.body.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)

                                ForEach([1024, 2048, 4096, 8192], id: \.self) { val in
                                    Button {
                                        agent.maxTokens = val
                                    } label: {
                                        Text("\(val / 1024)K")
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(agent.maxTokens == val
                                                ? Color.orange : Color.white.opacity(0.1))
                                            .foregroundColor(agent.maxTokens == val ? .black : .white)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    if agent.maxTokens < 8192 { agent.maxTokens += 256 }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.body.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        if !isNew && !agent.isBuiltin {
                            Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                            Button {
                                Task {
                                    if await agentsVM.deleteAgent(agent) { dismiss() }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Agent")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        }

                        // Bottom padding so scroll content isn't hidden behind save bar
                        Spacer().frame(height: 100)
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // ── STICKY SAVE BAR ──────────────────────────────────────
                VStack(spacing: 0) {
                    if let err = saveError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.9))
                    }

                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                        Task { await saveAgent() }
                    } label: {
                        HStack(spacing: 10) {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text(isSaving ? "Saving..." : (agent.name.isEmpty ? "Enter Name Above to Save" : "Save Agent"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(agent.name.isEmpty || isSaving ? Color.gray.opacity(0.5) : Color.orange)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.name.isEmpty || isSaving)
                }
                .background(bgColor.opacity(0.95))
            }
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
        }
    }

    private func saveAgent() async {
        saveError = nil
        isSaving = true
        agent.modelProvider = "mlx"

        if isNew {
            if await agentsVM.createAgent(agent) {
                dismiss()
            } else {
                saveError = agentsVM.errorMessage
            }
        } else {
            if await agentsVM.updateAgent(agent) {
                dismiss()
            } else {
                saveError = agentsVM.errorMessage
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
