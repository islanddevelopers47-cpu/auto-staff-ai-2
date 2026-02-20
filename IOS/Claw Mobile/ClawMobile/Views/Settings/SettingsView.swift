import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject var mlxService = MLXService.shared
    @State private var showSignOutAlert = false

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

                // Model Management Section
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
