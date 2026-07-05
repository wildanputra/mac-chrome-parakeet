import Foundation

public struct LocalLLMModelReference: Sendable, Equatable {
    public let modelName: String
    public let directory: URL

    public init(modelName: String, directory: URL) {
        self.modelName = modelName
        self.directory = directory
    }
}

public enum LocalLLMRuntimeEvent: Sendable, Equatable {
    case text(String)
    case metrics(LLMGenerationMetrics)
}

public protocol LocalLLMRuntime: Sendable {
    func load(model: LocalLLMModelReference) async throws
    func unload() async
    func generateStream(
        messages: [ChatMessage],
        options: ChatCompletionOptions
    ) async throws -> AsyncThrowingStream<LocalLLMRuntimeEvent, Error>
    func instrumentation() async -> LLMGenerationMetrics?
}

public actor UnavailableLocalLLMRuntime: LocalLLMRuntime {
    public init() {}

    public func load(model: LocalLLMModelReference) async throws {
        throw LLMError.modelNotFound(
            "Local MLX runtime is not linked in this build. Enable the gated app build and set \(InProcessLLMClient.modelDirectoryEnvironmentVariable) to a local model directory."
        )
    }

    public func unload() async {}

    public func generateStream(
        messages: [ChatMessage],
        options: ChatCompletionOptions
    ) async throws -> AsyncThrowingStream<LocalLLMRuntimeEvent, Error> {
        throw LLMError.modelNotFound("Local MLX runtime is not linked in this build.")
    }

    public func instrumentation() async -> LLMGenerationMetrics? {
        nil
    }
}
