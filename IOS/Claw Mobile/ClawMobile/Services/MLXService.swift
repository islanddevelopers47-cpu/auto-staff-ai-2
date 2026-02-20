import Foundation
import MLX
import MLXNN
import MLXRandom
import MLXLLM
import MLXLMCommon

/// Available on-device models for MLX inference
struct MLXModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let huggingFaceRepo: String
    let sizeDescription: String
    let deviceWarning: String?

    static let defaultModels: [MLXModelInfo] = [
        MLXModelInfo(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            sizeDescription: "~700 MB",
            deviceWarning: "Recommended: iPhone 15 Pro or newer"
        ),
        MLXModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeDescription: "~1.8 GB",
            deviceWarning: "Recommended: iPhone 15 Pro or newer"
        ),
        MLXModelInfo(
            id: "phi-3.5-mini",
            name: "Phi 3.5 Mini Instruct",
            huggingFaceRepo: "mlx-community/Phi-3.5-mini-instruct-4bit",
            sizeDescription: "~2.2 GB",
            deviceWarning: "Recommended: iPhone 16 or newer"
        ),
        MLXModelInfo(
            id: "gemma-2-2b",
            name: "Gemma 2 2B Instruct",
            huggingFaceRepo: "mlx-community/gemma-2-2b-it-4bit",
            sizeDescription: "~1.5 GB",
            deviceWarning: "Recommended: iPhone 15 Pro or newer"
        ),
    ]
}

/// Manages on-device LLM inference using MLX-Swift + MLXLLM
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

    // MARK: - Model State

    func isModelDownloaded(_ modelInfo: MLXModelInfo) -> Bool {
        downloadedModels.contains(modelInfo.id)
    }

    // MARK: - Download

    /// Downloads the model via HuggingFace Hub (handled by MLXLLM internally).
    /// Progress is reported through isDownloading / downloadProgress.
    func downloadModel(_ modelInfo: MLXModelInfo) async throws {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let configuration = ModelConfiguration(id: modelInfo.huggingFaceRepo)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        modelContainer = container
        currentModelId = modelInfo.id
        isModelLoaded = true
        downloadedModels.insert(modelInfo.id)
        saveDownloadedModelsList()
        downloadProgress = 1.0
    }

    // MARK: - Load / Unload

    /// Loads a previously downloaded model into memory.
    func loadModel(_ modelInfo: MLXModelInfo) async throws {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let configuration = ModelConfiguration(id: modelInfo.huggingFaceRepo)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        modelContainer = container
        currentModelId = modelInfo.id
        isModelLoaded = true
        downloadedModels.insert(modelInfo.id)
        saveDownloadedModelsList()
    }

    func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        currentModelId = nil
    }

    // MARK: - Delete

    func deleteModel(_ modelInfo: MLXModelInfo) throws {
        if currentModelId == modelInfo.id { unloadModel() }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let safeRepo = modelInfo.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelCache = caches.appendingPathComponent("huggingface/hub/models--\(safeRepo)")
        if FileManager.default.fileExists(atPath: modelCache.path) {
            try FileManager.default.removeItem(at: modelCache)
        }
        downloadedModels.remove(modelInfo.id)
        saveDownloadedModelsList()
    }

    // MARK: - Inference

    /// Generates a full response (non-streaming).
    func generate(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        userMessage: String,
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        guard let container = modelContainer else { throw MLXError.modelNotLoaded }

        isGenerating = true
        defer { isGenerating = false }

        let messages = buildMessages(systemPrompt: systemPrompt,
                                     history: conversationHistory,
                                     userMessage: userMessage)
        let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature))
        return try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: messages)
            )
            let stream = try generate(input: input, parameters: params, context: context)
            var result = ""
            for await generation in stream {
                if let chunk = generation.chunk { result += chunk }
            }
            return result
        }
    }

    /// Generates a response with streaming token callbacks.
    /// `onToken` receives the full accumulated text so far on each update.
    func generateStreaming(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        userMessage: String,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let container = modelContainer else { throw MLXError.modelNotLoaded }

        isGenerating = true
        defer { isGenerating = false }

        let messages = buildMessages(systemPrompt: systemPrompt,
                                     history: conversationHistory,
                                     userMessage: userMessage)
        let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature))
        try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: messages)
            )
            let stream = try generate(input: input, parameters: params, context: context)
            var text = ""
            for await generation in stream {
                if let chunk = generation.chunk {
                    text += chunk
                    DispatchQueue.main.async { onToken(text) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildMessages(
        systemPrompt: String,
        history: [(role: String, content: String)],
        userMessage: String
    ) -> [Chat.Message] {
        var msgs: [Chat.Message] = [Chat.Message(role: .system, content: systemPrompt)]
        for msg in history.suffix(20) {
            msgs.append(Chat.Message(
                role: msg.role == "user" ? .user : .assistant,
                content: msg.content
            ))
        }
        msgs.append(Chat.Message(role: .user, content: userMessage))
        return msgs
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
