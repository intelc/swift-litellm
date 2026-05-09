import Foundation
import LiteLLM

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
public struct AppleFoundationModelsProvider: ChatProvider {
    public let providerName = "apple-foundation-models"
    public let model: String
    public var apiKey: String? { nil }

    private let instructions: String?
    private let promptRenderer: @Sendable (ChatRequest) -> String

    public init(
        model: String = "system-language-model",
        instructions: String? = nil,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render
    ) {
        self.model = model
        self.instructions = instructions
        self.promptRenderer = promptRenderer
    }

    public func withAPIKey(_ apiKey: String) -> any ChatProvider {
        self
    }

    public func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        let session = makeSession()
        let response = try await session.respond(to: promptRenderer(request))
        return ChatResponse(
            model: model,
            message: .assistant(response.content),
            finishReason: "stop",
            provider: providerName
        )
    }

    public func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = makeSession()
                    var previous = ""
                    for try await snapshot in session.streamResponse(to: promptRenderer(request)) {
                        if Task.isCancelled { throw LiteLLMError.cancelled }
                        let content = snapshot.content
                        let delta = content.hasPrefix(previous) ? String(content.dropFirst(previous.count)) : content
                        previous = content
                        if !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                    }
                    continuation.yield(.messageCompleted(ChatResponse(
                        model: model,
                        message: .assistant(previous),
                        finishReason: "stop",
                        provider: providerName
                    )))
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func makeSession() -> LanguageModelSession {
        if let instructions, !instructions.isEmpty {
            return LanguageModelSession(instructions: instructions)
        }
        return LanguageModelSession()
    }
}

@available(iOS 26.0, macOS 26.0, *)
public extension Provider {
    static func appleFoundationModel(
        model: String = "system-language-model",
        instructions: String? = nil,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render
    ) -> Provider {
        Provider(chatProvider: AppleFoundationModelsProvider(
            model: model,
            instructions: instructions,
            promptRenderer: promptRenderer
        ))
    }
}
#else

public struct AppleFoundationModelsProvider: ChatProvider {
    public let providerName = "apple-foundation-models"
    public let model: String
    public var apiKey: String? { nil }

    public init(
        model: String = "system-language-model",
        instructions: String? = nil,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render
    ) {
        self.model = model
    }

    public func withAPIKey(_ apiKey: String) -> any ChatProvider {
        self
    }

    public func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        throw LiteLLMError.provider("Apple Foundation Models are not available in this SDK or on this platform")
    }

    public func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LiteLLMError.provider("Apple Foundation Models are not available in this SDK or on this platform"))
        }
    }
}

public extension Provider {
    static func appleFoundationModel(
        model: String = "system-language-model",
        instructions: String? = nil,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render
    ) -> Provider {
        Provider(chatProvider: AppleFoundationModelsProvider(
            model: model,
            instructions: instructions,
            promptRenderer: promptRenderer
        ))
    }
}
#endif
