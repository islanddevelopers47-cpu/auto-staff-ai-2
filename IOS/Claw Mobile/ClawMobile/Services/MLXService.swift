import Foundation
import MLX
import MLXNN
import MLXRandom

/// Available on-device models for MLX inference
struct MLXModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let huggingFaceRepo: String
    let sizeDescription: String

    static let defaultModels: [MLXModelInfo] = [
        MLXModelInfo(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            sizeDescription: "~700 MB"
        ),
        MLXModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeDescription: "~1.8 GB"
        ),
        MLXModelInfo(
            id: "phi-3.5-mini",
            name: "Phi 3.5 Mini Instruct",
            huggingFaceRepo: "mlx-community/Phi-3.5-mini-instruct-4bit",
            sizeDescription: "~2.2 GB"
        ),
        MLXModelInfo(
            id: "gemma-2-2b",
            name: "Gemma 2 2B Instruct",
            huggingFaceRepo: "mlx-community/gemma-2-2b-it-4bit",
            sizeDescription: "~1.5 GB"
        ),
    ]
}

/// Manages on-device LLM inference using MLX-Swift
@MainActor
class MLXService: ObservableObject {
    static let shared = MLXService()

    @Published var isModelLoaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isGenerating = false
    @Published var currentModelId: String?
    @Published var downloadedModels: Set<String> = []

    private var modelContainer: ModelContainer?

    private init() {
        loadDownloadedModelsList()
    }

    /// Directory where models are stored
    var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("mlx-models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Check if a model is downloaded
    func isModelDownloaded(_ modelInfo: MLXModelInfo) -> Bool {
        downloadedModels.contains(modelInfo.id)
    }

    /// Get the local path for a model
    func modelPath(for modelInfo: MLXModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(modelInfo.id, isDirectory: true)
    }

    /// Download a model from HuggingFace Hub
    func downloadModel(_ modelInfo: MLXModelInfo) async throws {
        isDownloading = true
        downloadProgress = 0

        defer {
            isDownloading = false
        }

        let destination = modelPath(for: modelInfo)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Download model files from HuggingFace
        let baseURL = "https://huggingface.co/\(modelInfo.huggingFaceRepo)/resolve/main"
        let filesToDownload = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.safetensors",
            "model.safetensors.index.json",
        ]

        for (index, filename) in filesToDownload.enumerated() {
            let fileURL = URL(string: "\(baseURL)/\(filename)")!
            let destFile = destination.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: destFile.path) {
                downloadProgress = Double(index + 1) / Double(filesToDownload.count)
                continue
            }

            do {
                let (tempURL, response) = try await URLSession.shared.download(from: fileURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    // Some files may not exist (e.g., index.json for small models), skip
                    continue
                }
                try FileManager.default.moveItem(at: tempURL, to: destFile)
            } catch {
                // Non-critical files can be skipped
                print("[MLXService] Skipping \(filename): \(error.localizedDescription)")
            }

            downloadProgress = Double(index + 1) / Double(filesToDownload.count)
        }

        downloadedModels.insert(modelInfo.id)
        saveDownloadedModelsList()
        downloadProgress = 1.0
    }

    /// Delete a downloaded model
    func deleteModel(_ modelInfo: MLXModelInfo) throws {
        if currentModelId == modelInfo.id {
            unloadModel()
        }
        let path = modelPath(for: modelInfo)
        try FileManager.default.removeItem(at: path)
        downloadedModels.remove(modelInfo.id)
        saveDownloadedModelsList()
    }

    /// Load a model for inference
    func loadModel(_ modelInfo: MLXModelInfo) async throws {
        guard isModelDownloaded(modelInfo) else {
            throw MLXError.modelNotDownloaded
        }

        // For now, we set the model as current. Full MLX-LM loading
        // requires the mlx-swift-lm package which provides ModelContainer.
        // This is a placeholder that will be connected when building with Xcode.
        currentModelId = modelInfo.id
        isModelLoaded = true
    }

    /// Unload the current model
    func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        currentModelId = nil
    }

    /// Generate a response from the loaded model
    func generate(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        userMessage: String,
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        guard isModelLoaded else {
            throw MLXError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build the prompt in chat format
        var prompt = "<|begin_of_text|>"
        prompt += "<|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"

        for msg in conversationHistory.suffix(20) {
            let role = msg.role == "user" ? "user" : "assistant"
            prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
        }

        prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(userMessage)<|eot_id|>"
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"

        // Placeholder response until full MLX-LM integration is built in Xcode
        // The actual inference pipeline requires ModelContainer from mlx-swift-lm
        // which handles tokenization, KV-cache, and token generation
        return "[MLX inference will be available after building with Xcode and mlx-swift-lm. Model: \(currentModelId ?? "none")]"
    }

    /// Generate with streaming callback
    func generateStreaming(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        userMessage: String,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: @escaping (String) -> Void
    ) async throws {
        let response = try await generate(
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userMessage: userMessage,
            temperature: temperature,
            maxTokens: maxTokens
        )
        // Simulate streaming for now
        for word in response.split(separator: " ") {
            onToken(String(word) + " ")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Persistence

    private func loadDownloadedModelsList() {
        if let data = UserDefaults.standard.data(forKey: "downloadedModels"),
           let models = try? JSONDecoder().decode(Set<String>.self, from: data) {
            downloadedModels = models
        }
    }

    private func saveDownloadedModelsList() {
        if let data = try? JSONEncoder().encode(downloadedModels) {
            UserDefaults.standard.set(data, forKey: "downloadedModels")
        }
    }
}

// MARK: - Placeholder for mlx-swift-lm ModelContainer

/// This will be replaced by the actual ModelContainer from mlx-swift-lm when building in Xcode
class ModelContainer {
    // Placeholder
}

// MARK: - Errors

enum MLXError: LocalizedError {
    case modelNotDownloaded
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "Model not downloaded. Please download it first."
        case .modelNotLoaded: return "No model loaded. Please load a model first."
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        }
    }
}
