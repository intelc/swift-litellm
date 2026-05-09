import Foundation
import LiteLLM

public typealias InProcessGenerateHandler = @Sendable (_ request: ChatRequest, _ prompt: String) async throws -> String
public typealias InProcessStreamHandler = @Sendable (_ request: ChatRequest, _ prompt: String) -> AsyncThrowingStream<String, Error>
public typealias InProcessCancelHandler = @Sendable () -> Void

public struct InProcessLanguageModelProvider: ChatProvider {
    public let providerName: String
    public let model: String
    public var apiKey: String? { nil }

    private let promptRenderer: @Sendable (ChatRequest) -> String
    private let generate: InProcessGenerateHandler
    private let stream: InProcessStreamHandler?
    private let cancel: InProcessCancelHandler?

    public init(
        providerName: String,
        model: String,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render,
        generate: @escaping InProcessGenerateHandler,
        stream: InProcessStreamHandler? = nil,
        cancel: InProcessCancelHandler? = nil
    ) {
        self.providerName = providerName
        self.model = model
        self.promptRenderer = promptRenderer
        self.generate = generate
        self.stream = stream
        self.cancel = cancel
    }

    public func withAPIKey(_ apiKey: String) -> any ChatProvider {
        self
    }

    public func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        let text = try await generate(request, promptRenderer(request))
        return ChatResponse(
            model: model,
            message: .assistant(text),
            finishReason: "stop",
            provider: providerName
        )
    }

    public func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let stream else {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let response = try await chat(request, context: context)
                        if let text = response.message.content?.textValue, !text.isEmpty {
                            continuation.yield(.textDelta(text))
                        }
                        continuation.yield(.messageCompleted(response))
                        continuation.yield(.done)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    cancel?()
                    task.cancel()
                }
            }
        }

        let textStream = stream(request, promptRenderer(request))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var fullText = ""
                    for try await delta in textStream {
                        if Task.isCancelled { throw LiteLLMError.cancelled }
                        fullText += delta
                        continuation.yield(.textDelta(delta))
                    }
                    continuation.yield(.messageCompleted(ChatResponse(
                        model: model,
                        message: .assistant(fullText),
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
                cancel?()
                task.cancel()
            }
        }
    }
}

public enum LocalPromptRenderer {
    public static func render(_ request: ChatRequest) -> String {
        request.messages
            .map(render)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func render(_ message: LLMMessage) -> String {
        let role = message.role.rawValue.uppercased()
        var lines: [String] = []
        if let content = message.content {
            lines.append("\(role): \(render(content))")
        }
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            for call in toolCalls {
                lines.append("ASSISTANT_TOOL_CALL \(call.name): \(call.arguments)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ content: LLMContent) -> String {
        switch content {
        case let .text(text):
            text
        case let .parts(parts):
            parts.map(render).joined(separator: "\n")
        }
    }

    private static func render(_ part: LLMContentPart) -> String {
        switch part {
        case let .text(text):
            text
        case let .imageURL(url):
            "[image: \(url)]"
        }
    }
}

public extension Provider {
    static func inProcess(
        providerName: String,
        model: String,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render,
        generate: @escaping InProcessGenerateHandler,
        stream: InProcessStreamHandler? = nil,
        cancel: InProcessCancelHandler? = nil
    ) -> Provider {
        Provider(chatProvider: InProcessLanguageModelProvider(
            providerName: providerName,
            model: model,
            promptRenderer: promptRenderer,
            generate: generate,
            stream: stream,
            cancel: cancel
        ))
    }

    static func mlxInProcess(
        model: String,
        promptRenderer: @escaping @Sendable (ChatRequest) -> String = LocalPromptRenderer.render,
        generate: @escaping InProcessGenerateHandler,
        stream: InProcessStreamHandler? = nil,
        cancel: InProcessCancelHandler? = nil
    ) -> Provider {
        .inProcess(
            providerName: "mlx",
            model: model,
            promptRenderer: promptRenderer,
            generate: generate,
            stream: stream,
            cancel: cancel
        )
    }
}
