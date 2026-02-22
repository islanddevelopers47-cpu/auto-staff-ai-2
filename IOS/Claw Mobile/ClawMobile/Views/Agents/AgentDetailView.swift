import SwiftUI

struct AgentDetailView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @Environment(\.dismiss) var dismiss

    @State var agent: Agent
    var isNew: Bool = false

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var selectedProvider: String = "openai"

    private let cloudProviders: [(id: String, label: String, icon: String, models: [(id: String, label: String)])] = [
        (id: "openai",    label: "OpenAI",    icon: "cloud.fill",  models: [
            (id: "gpt-4o",       label: "GPT-4o"),
            (id: "gpt-4o-mini",  label: "GPT-4o Mini"),
            (id: "gpt-4-turbo",  label: "GPT-4 Turbo"),
            (id: "gpt-3.5-turbo",label: "GPT-3.5 Turbo"),
        ]),
        (id: "anthropic", label: "Anthropic", icon: "cloud.fill",  models: [
            (id: "claude-opus-4-5",         label: "Claude Opus 4.5"),
            (id: "claude-sonnet-4-5",       label: "Claude Sonnet 4.5"),
            (id: "claude-haiku-3-5",        label: "Claude Haiku 3.5"),
        ]),
        (id: "google",    label: "Gemini",    icon: "cloud.fill",  models: [
            (id: "gemini-2.0-flash",         label: "Gemini 2.0 Flash"),
            (id: "gemini-1.5-pro",           label: "Gemini 1.5 Pro"),
            (id: "gemini-1.5-flash",         label: "Gemini 1.5 Flash"),
        ]),
        (id: "grok",      label: "Grok",      icon: "cloud.fill",  models: [
            (id: "grok-3",       label: "Grok 3"),
            (id: "grok-3-mini",  label: "Grok 3 Mini"),
            (id: "grok-2",       label: "Grok 2"),
        ]),
    ]

    private let bgColor = Color(red: 0.08, green: 0.04, blue: 0.12)

    var body: some View {
        ScrollView {
                VStack(spacing: 0) {

                    // ── NAME ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent Name *")
                            .font(.caption).foregroundColor(.gray)
                        TextField("Enter a name to enable Save", text: $agent.name)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .submitLabel(.done)
                        if agent.name.isEmpty {
                            Text("Name is required to save")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal).padding(.top, 16).padding(.bottom, 12)

                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                    // ── DESCRIPTION ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description (optional)")
                            .font(.caption).foregroundColor(.gray)
                        TextField("Short description", text: Binding(
                            get: { agent.description ?? "" },
                            set: { agent.description = $0.isEmpty ? nil : $0 }
                        ))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                    // ── SYSTEM PROMPT ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(.caption).foregroundColor(.gray)
                        TextField("You are a helpful assistant...", text: $agent.systemPrompt, axis: .vertical)
                            .lineLimit(5...10)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                    // ── MODEL ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Provider").font(.caption).foregroundColor(.gray)

                        // Provider tabs
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Cloud providers
                                ForEach(cloudProviders, id: \.id) { provider in
                                    Button {
                                        selectedProvider = provider.id
                                        agent.modelProvider = provider.id
                                        agent.modelName = provider.models.first?.id ?? ""
                                    } label: {
                                        Text(provider.label)
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedProvider == provider.id
                                                ? Color.orange : Color.white.opacity(0.08))
                                            .foregroundColor(selectedProvider == provider.id ? .black : .white)
                                            .cornerRadius(20)
                                    }
                                    .buttonStyle(.plain)
                                }
                                // MLX on-device
                                Button {
                                    selectedProvider = "mlx"
                                    agent.modelProvider = "mlx"
                                    agent.modelName = MLXModelInfo.defaultModels.first?.huggingFaceRepo ?? ""
                                } label: {
                                    Text("On-Device")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedProvider == "mlx"
                                            ? Color.purple : Color.white.opacity(0.08))
                                        .foregroundColor(.white)
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 1)
                        }

                        // Model list for selected provider
                        Text("Model").font(.caption).foregroundColor(.gray)

                        if selectedProvider == "mlx" {
                            ForEach(MLXModelInfo.defaultModels) { model in
                                Button {
                                    agent.modelName = model.huggingFaceRepo
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.name).foregroundColor(.white).font(.subheadline)
                                            Text("On-device · \(model.size)").font(.caption).foregroundColor(.gray)
                                        }
                                        Spacer()
                                        if agent.modelName == model.huggingFaceRepo {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.purple)
                                        }
                                    }
                                    .padding(12)
                                    .background(agent.modelName == model.huggingFaceRepo
                                        ? Color.purple.opacity(0.15) : Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if let provider = cloudProviders.first(where: { $0.id == selectedProvider }) {
                            ForEach(provider.models, id: \.id) { model in
                                Button {
                                    agent.modelName = model.id
                                } label: {
                                    HStack {
                                        Text(model.label).foregroundColor(.white).font(.subheadline)
                                        Spacer()
                                        if agent.modelName == model.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                                        }
                                    }
                                    .padding(12)
                                    .background(agent.modelName == model.id
                                        ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                    // ── TEMPERATURE ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Temperature").font(.caption).foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.1f", agent.temperature))
                                .fontWeight(.bold).foregroundColor(.orange)
                        }
                        HStack(spacing: 8) {
                            ForEach([0.0, 0.5, 0.7, 1.0, 1.5, 2.0], id: \.self) { val in
                                Button { agent.temperature = val } label: {
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
                    .padding(.horizontal).padding(.vertical, 12)

                    Divider().background(Color.white.opacity(0.1)).padding(.horizontal)

                    // ── MAX TOKENS ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Max Tokens").font(.caption).foregroundColor(.gray)
                            Spacer()
                            Text("\(agent.maxTokens)").fontWeight(.bold).foregroundColor(.orange)
                        }
                        HStack(spacing: 8) {
                            Button { if agent.maxTokens > 256 { agent.maxTokens -= 256 } } label: {
                                Image(systemName: "minus").font(.body.bold())
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Color.white.opacity(0.1)).foregroundColor(.white)
                                    .cornerRadius(8)
                            }.buttonStyle(.plain)

                            ForEach([1024, 2048, 4096, 8192], id: \.self) { val in
                                Button { agent.maxTokens = val } label: {
                                    Text("\(val / 1024)K").font(.subheadline.bold())
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(agent.maxTokens == val
                                            ? Color.orange : Color.white.opacity(0.1))
                                        .foregroundColor(agent.maxTokens == val ? .black : .white)
                                        .cornerRadius(8)
                                }.buttonStyle(.plain)
                            }

                            Button { if agent.maxTokens < 8192 { agent.maxTokens += 256 } } label: {
                                Image(systemName: "plus").font(.body.bold())
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Color.white.opacity(0.1)).foregroundColor(.white)
                                    .cornerRadius(8)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    if !isNew && !agent.isBuiltin {
                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)
                        Button {
                            Task { if await agentsVM.deleteAgent(agent) { dismiss() } }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Agent")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.red.opacity(0.15)).foregroundColor(.red)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal).padding(.vertical, 12)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(bgColor.ignoresSafeArea())
            .onAppear {
                selectedProvider = agent.modelProvider.isEmpty ? "openai" : agent.modelProvider
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let err = saveError {
                        Text(err)
                            .font(.caption).foregroundColor(.white)
                            .padding(10).frame(maxWidth: .infinity)
                            .background(Color.red)
                    }
                    Button {
                        Task { await saveAgent() }
                    } label: {
                        HStack(spacing: 10) {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving..."
                                : (agent.name.isEmpty ? "Enter a Name to Save" : "Save Agent"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(agent.name.isEmpty || isSaving
                            ? Color.gray.opacity(0.4) : Color.orange)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.name.isEmpty || isSaving)
                }
                .background(bgColor)
            }
        .navigationTitle(isNew ? "New Agent" : agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.gray)
                }
            }
        }
    }

    private func saveAgent() async {
        saveError = nil
        isSaving = true
        agent.modelProvider = selectedProvider

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
