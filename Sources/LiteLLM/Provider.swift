import Foundation

public struct Provider: Sendable {
    private let chatProvider: any ChatProvider

    public init(adapter: any ProviderAdapter) {
        chatProvider = HTTPAdapterChatProvider(adapter: adapter)
    }

    public init(chatProvider: any ChatProvider) {
        self.chatProvider = chatProvider
    }

    public var model: String {
        chatProvider.model
    }

    public var providerName: String {
        chatProvider.providerName
    }

    public var apiKey: String? {
        chatProvider.apiKey
    }

    func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        try await chatProvider.chat(request, context: context)
    }

    func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        chatProvider.streamChat(request, context: context)
    }

    func withAPIKey(_ apiKey: String) -> Provider {
        Provider(chatProvider: chatProvider.withAPIKey(apiKey))
    }
}

public extension Provider {
    static func openAICompatible(
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        providerName: String = "openai-compatible"
    ) -> Provider {
        Provider(adapter: OpenAICompatibleAdapter(baseURL: baseURL, apiKey: apiKey, model: model, providerName: providerName))
    }

    static func anthropic(baseURL: URL = URL(string: "https://api.anthropic.com")!, apiKey: String? = nil, model: String) -> Provider {
        Provider(adapter: AnthropicAdapter(baseURL: baseURL, apiKey: apiKey, model: model))
    }

    static func gemini(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!, apiKey: String? = nil, model: String) -> Provider {
        Provider(adapter: GeminiAdapter(baseURL: baseURL, apiKey: apiKey, model: model))
    }

    static func ollama(baseURL: URL = URL(string: "http://localhost:11434")!, model: String) -> Provider {
        Provider(adapter: OllamaAdapter(baseURL: baseURL, model: model))
    }
}

public struct ProviderHTTPRequest: Equatable, Sendable {
    public var url: URL
    public var headers: [String: String]
    public var body: [String: JSONValue]
    public var streamBody: Bool

    public init(url: URL, headers: [String: String], body: [String: JSONValue], streamBody: Bool) {
        self.url = url
        self.headers = headers
        self.body = body
        self.streamBody = streamBody
    }
}

public protocol ProviderAdapter: Sendable {
    var providerName: String { get }
    var model: String { get }
    var apiKey: String? { get }
    func withAPIKey(_ apiKey: String) -> any ProviderAdapter
    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest
    func parseResponse(data: Data) throws -> ChatResponse
    func parseStreamLine(_ line: String) throws -> [StreamEvent]
}

public struct ProviderContext: Sendable {
    public let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }
}

public protocol ChatProvider: Sendable {
    var providerName: String { get }
    var model: String { get }
    var apiKey: String? { get }
    func withAPIKey(_ apiKey: String) -> any ChatProvider
    func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse
    func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error>
}

private struct HTTPAdapterChatProvider: ChatProvider {
    let adapter: any ProviderAdapter

    var providerName: String { adapter.providerName }
    var model: String { adapter.model }
    var apiKey: String? { adapter.apiKey }

    func withAPIKey(_ apiKey: String) -> any ChatProvider {
        HTTPAdapterChatProvider(adapter: adapter.withAPIKey(apiKey))
    }

    func chat(_ request: ChatRequest, context: ProviderContext) async throws -> ChatResponse {
        let providerRequest = try adapter.makeRequest(request, stream: false)
        let httpRequest = try makeHTTPRequest(providerRequest)
        let (data, response) = try await context.transport.data(for: httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw LiteLLMError.transport(
                statusCode: response.statusCode,
                body: normalizedProviderErrorBody(data, provider: adapter.providerName)
            )
        }
        return try adapter.parseResponse(data: data)
    }

    func streamChat(_ request: ChatRequest, context: ProviderContext) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let providerRequest = try adapter.makeRequest(request, stream: true)
                    let httpRequest = try makeHTTPRequest(providerRequest)
                    let (bytes, response) = try await context.transport.bytes(for: httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw LiteLLMError.transport(statusCode: response.statusCode, body: "")
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw LiteLLMError.cancelled }
                        for event in try adapter.parseStreamLine(line) {
                            continuation.yield(event)
                            if event == .done {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error.asLiteLLMError)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func makeHTTPRequest(_ providerRequest: ProviderHTTPRequest) throws -> HTTPRequest {
        HTTPRequest(
            url: providerRequest.url,
            method: "POST",
            headers: providerRequest.headers,
            body: try JSONCoding.data(providerRequest.body)
        )
    }
}
