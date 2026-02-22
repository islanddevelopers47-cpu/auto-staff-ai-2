import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject var mlxService = MLXService.shared
    @State private var showSignOutAlert = false
    @State private var apiKeys: [UserApiKey] = []
    @State private var showAddKeySheet = false
    @State private var apiKeyError: String?

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    if let user = authViewModel.currentUser {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                Text(user.initials)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName ?? "User")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))

                // API Keys Section
                Section {
                    ForEach(apiKeys) { key in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(key.provider.capitalized)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    if let label = key.label, !label.isEmpty {
                                        Text(label)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Text(key.maskedKey ?? "••••••••")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .fontDesign(.monospaced)
                            }
                            Spacer()
                            Button {
                                Task {
                                    try? await APIService.shared.deleteApiKey(id: key.id)
                                    await loadApiKeys()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        showAddKeySheet = true
                    } label: {
                        Label("Add API Key", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("Add your OpenAI (or other provider) API key to use cloud agents via Railway.")
                        .font(.caption2)
                }
                .listRowBackground(Color.white.opacity(0.06))

                // On-Device Models Section
                Section {
                    ForEach(MLXModelInfo.defaultModels) { model in
                        ModelRow(model: model, mlxService: mlxService)
                    }
                } header: {
                    Text("On-Device Models (MLX)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Models run entirely on your device. No data is sent to external servers.")
                            .font(.caption2)
                        Text("⚠️ On-device AI is recommended for iPhone 15 Pro or newer. Older devices may be slow or crash.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))

                // About Section
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("AI Engine")
                        Spacer()
                        Text("MLX Swift")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text("iOS 17+")
                            .foregroundColor(.gray)
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Settings")
            .task { await loadApiKeys() }
            .sheet(isPresented: $showAddKeySheet, onDismiss: { Task { await loadApiKeys() } }) {
                AddApiKeySheet()
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func loadApiKeys() async {
        apiKeys = (try? await APIService.shared.fetchApiKeys()) ?? []
    }
}

// MARK: - Add API Key Sheet

struct AddApiKeySheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedProvider = "openai"
    @State private var apiKeyText = ""
    @State private var labelText = ""
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var testResult: Bool? = nil
    @State private var errorMessage: String?

    let providers = ["openai", "anthropic", "google", "grok"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providers, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section("API Key") {
                    SecureField("sk-...", text: $apiKeyText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Label (optional)", text: $labelText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Color.white.opacity(0.06))

                if let result = testResult {
                    Section {
                        HStack {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result ? .green : .red)
                            Text(result ? "Key is valid" : "Key is invalid or rejected")
                                .foregroundColor(result ? .green : .red)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }

                Section {
                    Button {
                        Task { await testKey() }
                    } label: {
                        HStack {
                            if isTesting { ProgressView().scaleEffect(0.8) }
                            Text("Test Key")
                        }
                        .foregroundColor(.orange)
                    }
                    .disabled(apiKeyText.isEmpty || isTesting || isSaving)

                    Button {
                        Task { await saveKey() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().scaleEffect(0.8) }
                            Text("Save Key")
                        }
                        .foregroundColor(.white)
                    }
                    .disabled(apiKeyText.isEmpty || isSaving || isTesting)
                }
                .listRowBackground(Color.orange.opacity(0.2))
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.04, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.gray)
                }
            }
        }
    }

    private func testKey() async {
        isTesting = true
        testResult = nil
        errorMessage = nil
        do {
            testResult = try await APIService.shared.testApiKey(provider: selectedProvider, apiKey: apiKeyText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isTesting = false
    }

    private func saveKey() async {
        isSaving = true
        errorMessage = nil
        do {
            try await APIService.shared.saveApiKey(
                provider: selectedProvider,
                apiKey: apiKeyText,
                label: labelText.isEmpty ? nil : labelText
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}


// MARK: - Model Row

struct ModelRow: View {
    let model: MLXModelInfo
    @ObservedObject var mlxService: MLXService
    @State private var isDownloading = false
    @State private var showDeleteAlert = false

    var isDownloaded: Bool {
        mlxService.isModelDownloaded(model)
    }

    var isLoaded: Bool {
        mlxService.currentModelId == model.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        if isLoaded {
                            Text("Active")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                    if let warning = model.deviceWarning {
                        Text(warning)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()

                if isDownloading || (mlxService.isDownloading && mlxService.downloadProgress > 0) {
                    VStack(spacing: 4) {
                        ProgressView(value: mlxService.downloadProgress)
                            .tint(.orange)
                            .frame(width: 60)
                        Text("\(Int(mlxService.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                } else if isDownloaded {
                    HStack(spacing: 8) {
                        if !isLoaded {
                            Button {
                                Task {
                                    try? await mlxService.loadModel(model)
                                }
                            } label: {
                                Text("Load")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                            }
                        } else {
                            Button {
                                mlxService.unloadModel()
                            } label: {
                                Text("Unload")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }

                        Button {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Button {
                        downloadModel()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Model", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? mlxService.deleteModel(model)
            }
        } message: {
            Text("Delete \(model.name)? You can re-download it later.")
        }
    }

    private func downloadModel() {
        isDownloading = true
        Task {
            do {
                try await mlxService.downloadModel(model)
            } catch {
                print("Download failed: \(error)")
            }
            isDownloading = false
        }
    }
}
