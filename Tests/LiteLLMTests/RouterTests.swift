import Foundation
import LiteLLMLocalInference
import Testing
@testable import LiteLLM

@Suite("Router")
struct RouterTests {
    @Test func aliasResolvesToConfiguredProvider() async throws {
        let transport = MockHTTPTransport(responses: [(200, openAIResponse("primary"))])
        let client = LiteLLMClient(
            models: [
                "fast": .openAICompatible(baseURL: URL(string: "https://openrouter.ai/api")!, apiKey: "key", model: "openai/gpt-4o-mini"),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "fast", messages: [.user("Hello")])

        #expect(response.message.content == .text("primary"))
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.url.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test func customProviderAdapterCanBeRouted() async throws {
        let transport = MockHTTPTransport(responses: [(200, Data(#"{"content":"custom"}"#.utf8))])
        let client = LiteLLMClient(
            models: [
                "custom": Provider(adapter: StaticAdapter(model: "static-model")),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "custom", messages: [.user("Hello")])

        #expect(response.provider == "static")
        #expect(response.message.content == .text("custom"))
        #expect(await transport.requests.first?.url.absoluteString == "https://static.example.test/chat")
    }

    @Test func directChatProviderCanBypassHTTPTransport() async throws {
        let transport = MockHTTPTransport(responses: [(500, Data("should not be used".utf8))])
        let client = LiteLLMClient(
            models: [
                "direct": Provider(chatProvider: DirectChatProvider(model: "in-process-model")),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "direct", messages: [.user("Hello")])

        #expect(response.provider == "direct")
        #expect(response.message.content == .text("in process"))
        #expect(await transport.requests.isEmpty)
    }

    @Test func mlxInProcessProviderUsesRenderedPromptAndBypassesHTTP() async throws {
        let transport = MockHTTPTransport(responses: [(500, Data("should not be used".utf8))])
        let client = LiteLLMClient(
            models: [
                "mlx": .mlxInProcess(model: "mlx-community/test") { _, prompt in
                    "prompt: \(prompt)"
                },
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "mlx", messages: [.system("Be terse."), .user("Hello")])

        #expect(response.provider == "mlx")
        #expect(response.message.content == .text("prompt: SYSTEM: Be terse.\n\nUSER: Hello"))
        #expect(await transport.requests.isEmpty)
    }

    @Test func inProcessProviderStreamsTextDeltas() async throws {
        let client = LiteLLMClient(
            models: [
                "local": .inProcess(
                    providerName: "local-runtime",
                    model: "closure-model",
                    generate: { _, _ in "unused" },
                    stream: { _, _ in
                        AsyncThrowingStream { continuation in
                            continuation.yield("hel")
                            continuation.yield("lo")
                            continuation.finish()
                        }
                    }
                ),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: MockHTTPTransport(responses: [])
        )

        let stream = try client.streamChat(model: "local", messages: [.user("Hello")])
        let response = try await collectChatResponse(from: stream, model: "closure-model", provider: "local-runtime")

        #expect(response.message.content == .text("hello"))
        #expect(response.provider == "local-runtime")
    }

    @Test func inProcessStreamCancellationInvokesCancelHook() async throws {
        let recorder = StreamCancellationRecorder()
        let client = LiteLLMClient(
            models: [
                "local": .inProcess(
                    providerName: "local-runtime",
                    model: "closure-model",
                    generate: { _, _ in "unused" },
                    stream: { _, _ in
                        AsyncThrowingStream { continuation in
                            continuation.yield("first")
                            continuation.onTermination = { termination in
                                Task { await recorder.setStreamTermination(termination) }
                            }
                        }
                    },
                    cancel: {
                        Task { await recorder.setCancelCalled() }
                    }
                ),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: MockHTTPTransport(responses: [])
        )

        var stream: AsyncThrowingStream<StreamEvent, Error>? = try client.streamChat(model: "local", messages: [.user("Hello")])
        var iterator: AsyncThrowingStream<StreamEvent, Error>.Iterator? = stream?.makeAsyncIterator()
        _ = try await iterator?.next()
        iterator = nil
        stream = nil

        #expect(await recorder.waitForCancel() == true)
    }

    #if !canImport(FoundationModels)
    @Test func appleFoundationModelsStubIsRouteableWhenFrameworkIsUnavailable() async {
        let client = LiteLLMClient(
            models: [
                "apple": .appleFoundationModel(),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: MockHTTPTransport(responses: [])
        )

        await #expect(throws: LiteLLMError.self) {
            _ = try await client.chat(model: "apple", messages: [.user("Hello")])
        }
    }
    #endif

    @Test func localInferenceModulePresetsUseOpenAICompatibleShape() async throws {
        let transport = MockHTTPTransport(responses: [(200, openAIResponse("local"))])
        let client = LiteLLMClient(
            models: [
                "local": .lmStudio(model: "qwen2.5"),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "local", messages: [.user("Hello")])

        #expect(response.provider == "lm-studio")
        #expect(response.message.content == .text("local"))
        #expect(await transport.requests.first?.url.absoluteString == "http://localhost:1234/v1/chat/completions")
    }

    @Test func fallbackChainTriesNextModelOnRetryableError() async throws {
        let transport = MockHTTPTransport(responses: [
            (500, Data("upstream down".utf8)),
            (200, ollamaResponse("local")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "smart", messages: [.user("Hello")])

        #expect(response.message.content == .text("local"))
        #expect(await transport.requests.map(\.url.path) == ["/v1/chat/completions", "/api/chat"])
    }

    @Test func nonRetryableDecodingErrorDoesNotFallback() async throws {
        let transport = MockHTTPTransport(responses: [
            (200, Data("{\"not\":\"a chat response\"}".utf8)),
            (200, ollamaResponse("should not happen")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        await #expect(throws: LiteLLMError.self) {
            _ = try await client.chat(model: "smart", messages: [.user("Hello")])
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func retryHappensBeforeFallback() async throws {
        let transport = MockHTTPTransport(responses: [
            (500, Data("first failure".utf8)),
            (200, openAIResponse("retried")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 1),
            transport: transport
        )

        let response = try await client.chat(model: "smart", messages: [.user("Hello")])

        #expect(response.message.content == .text("retried"))
        #expect(await transport.requests.map(\.url.path) == ["/v1/chat/completions", "/v1/chat/completions"])
    }

    @Test func cancellationDoesNotContinueFallbacks() async {
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: SlowHTTPTransport()
        )

        let task = Task {
            try await client.chat(model: "smart", messages: [.user("Hello")])
        }
        task.cancel()

        await #expect(throws: LiteLLMError.cancelled) {
            _ = try await task.value
        }
    }

    private func openAIResponse(_ content: String) -> Data {
        Data("""
        {
          "id": "chatcmpl_1",
          "model": "gpt",
          "choices": [{
            "message": {"role": "assistant", "content": "\(content)"},
            "finish_reason": "stop"
          }]
        }
        """.utf8)
    }

    private func ollamaResponse(_ content: String) -> Data {
        Data("""
        {
          "model": "llama3.2",
          "message": {"role": "assistant", "content": "\(content)"},
          "done": true
        }
        """.utf8)
    }
}

private struct StaticAdapter: ProviderAdapter {
    let model: String
    var providerName: String { "static" }
    var apiKey: String? { nil }

    func withAPIKey(_ apiKey: String) -> any ProviderAdapter {
        self
    }

    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest {
        ProviderHTTPRequest(
            url: URL(string: "https://static.example.test/chat")!,
            headers: request.extraHeaders,
            body: ["model": .string(model), "stream": .bool(stream)],
            streamBody: stream
        )
    }

    func parseResponse(data: Data) throws -> ChatResponse {
        let payload = try JSONDecoder().decode(StaticPayload.self, from: data)
        return ChatResponse(
            model: model,
            message: .assistant(payload.content),
            finishReason: "stop",
            provider: providerName
        )
    }

    func parseStreamLine(_ line: String) throws -> [StreamEvent] {
        []
    }

    private struct StaticPayload: Decodable {
        let content: String
    }
}

private struct DirectChatProvider: ChatProvider {
    let model: String
    var providerName: String { "direct" }
    var apiKey: String? { nil }

    func withAPIKey(_ apiKey: String) -> any ChatProvider {
        self
    }

    func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        ChatResponse(
            model: model,
            message: .assistant("in process"),
            finishReason: "stop",
            provider: providerName
        )
    }

    func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("in process"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private actor StreamCancellationRecorder {
    private var value: AsyncThrowingStream<String, Error>.Continuation.Termination?
    private var cancelCalled = false

    func setStreamTermination(_ termination: AsyncThrowingStream<String, Error>.Continuation.Termination) {
        value = termination
    }

    func setCancelCalled() {
        cancelCalled = true
    }

    func waitForCancel(timeout: Duration = .seconds(1)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if cancelCalled {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return cancelCalled
    }
}

private extension AsyncThrowingStream<String, Error>.Continuation.Termination {
    var isCancelled: Bool {
        if case .cancelled = self { true } else { false }
    }
}
