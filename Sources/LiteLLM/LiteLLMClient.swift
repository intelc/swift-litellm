import Foundation

public typealias APIKeyProvider = @Sendable (_ provider: Provider, _ alias: ModelAlias) throws -> String?

public final class LiteLLMClient: Sendable {
    private let models: [ModelAlias: Provider]
    private let fallbackPolicy: FallbackPolicy
    private let retryPolicy: RetryPolicy
    private let transport: any HTTPTransport
    private let apiKeyProvider: APIKeyProvider?

    public convenience init(
        models: [ModelAlias: Provider],
        fallbacks: [String: [String]] = [:],
        retryPolicy: RetryPolicy = RetryPolicy(),
        apiKeyProvider: APIKeyProvider? = nil
    ) {
        self.init(
            models: models,
            fallbackPolicy: FallbackPolicy(fallbacks),
            retryPolicy: retryPolicy,
            transport: URLSessionHTTPTransport(),
            apiKeyProvider: apiKeyProvider
        )
    }

    init(
        models: [ModelAlias: Provider],
        fallbackPolicy: FallbackPolicy,
        retryPolicy: RetryPolicy,
        transport: any HTTPTransport,
        apiKeyProvider: APIKeyProvider? = nil
    ) {
        self.models = models
        self.fallbackPolicy = fallbackPolicy
        self.retryPolicy = retryPolicy
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
    }

    public func chat(
        model alias: ModelAlias,
        messages: [LLMMessage],
        tools: [ToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        responseFormat: ResponseFormat? = nil,
        extraHeaders: [String: String] = [:],
        extraBody: [String: JSONValue] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) async throws -> ChatResponse {
        let request = ChatRequest(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            responseFormat: responseFormat,
            extraHeaders: extraHeaders,
            extraBody: extraBody,
            providerOptions: providerOptions
        )
        return try await chat(model: alias, request: request)
    }

    public func chat(model alias: ModelAlias, request: ChatRequest) async throws -> ChatResponse {
        let aliases = try route(for: alias)
        var lastError: LiteLLMError?
        for routeAlias in aliases {
            if Task.isCancelled { throw LiteLLMError.cancelled }
            do {
                return try await executeChat(model: routeAlias, request: request)
            } catch {
                let liteError = error.asLiteLLMError
                if liteError == .cancelled {
                    throw liteError
                }
                lastError = liteError
                guard shouldFallback(after: liteError) else {
                    throw liteError
                }
            }
        }
        throw lastError ?? LiteLLMError.unknownModelAlias(alias)
    }

    public func supports(_ capability: ModelCapability, model alias: ModelAlias) -> Bool {
        guard let provider = models[alias] else { return false }
        return ModelMetadata.supports(capability, model: provider.model)
            || ModelMetadata.supports(capability, model: alias)
    }

    public func streamChat(
        model alias: ModelAlias,
        messages: [LLMMessage],
        tools: [ToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        responseFormat: ResponseFormat? = nil,
        extraHeaders: [String: String] = [:],
        extraBody: [String: JSONValue] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = ChatRequest(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            responseFormat: responseFormat,
            extraHeaders: extraHeaders,
            extraBody: extraBody,
            providerOptions: providerOptions
        )
        return try streamChat(model: alias, request: request)
    }

    public func streamChat(model alias: ModelAlias, request: ChatRequest) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let aliases = try route(for: alias)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: LiteLLMError?
                for routeAlias in aliases {
                    do {
                        if Task.isCancelled { throw LiteLLMError.cancelled }
                        try await executeStream(model: routeAlias, request: request, continuation: continuation)
                        continuation.finish()
                        return
                    } catch {
                        let liteError = error.asLiteLLMError
                        if liteError == .cancelled {
                            continuation.finish(throwing: liteError)
                            return
                        }
                        lastError = liteError
                        guard shouldFallback(after: liteError) else {
                            continuation.finish(throwing: liteError)
                            return
                        }
                    }
                }
                continuation.finish(throwing: lastError ?? LiteLLMError.unknownModelAlias(alias))
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func executeChat(model alias: ModelAlias, request: ChatRequest) async throws -> ChatResponse {
        let provider = try provider(for: alias, request: request)
        let context = ProviderContext(transport: transport)

        var attempt = 0
        while true {
            if Task.isCancelled { throw LiteLLMError.cancelled }
            do {
                return try await provider.chat(request, context: context)
            } catch {
                let liteError = error.asLiteLLMError
                guard attempt < retryPolicy.maxRetries, isRetryable(liteError) else {
                    throw liteError
                }
                attempt += 1
            }
        }
    }

    private func executeStream(model alias: ModelAlias, request: ChatRequest, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let provider = try provider(for: alias, request: request)
        let stream = provider.streamChat(request, context: ProviderContext(transport: transport))
        for try await event in stream {
            if Task.isCancelled { throw LiteLLMError.cancelled }
            continuation.yield(event)
            if event == .done {
                return
            }
        }
    }

    private func route(for alias: ModelAlias) throws -> [ModelAlias] {
        guard models[alias] != nil else {
            throw LiteLLMError.unknownModelAlias(alias)
        }
        return [alias] + (fallbackPolicy.fallbacks[alias] ?? [])
    }

    private func provider(for alias: ModelAlias) throws -> Provider {
        guard let provider = models[alias] else {
            throw LiteLLMError.unknownModelAlias(alias)
        }
        return provider
    }

    private func provider(for alias: ModelAlias, request: ChatRequest) throws -> Provider {
        let provider = try provider(for: alias)
        if let override = request.providerOptions.apiKeyOverride {
            return provider.withAPIKey(override)
        }
        guard provider.apiKey == nil, let apiKeyProvider else {
            return provider
        }
        guard let apiKey = try apiKeyProvider(provider, alias), !apiKey.isEmpty else {
            return provider
        }
        return provider.withAPIKey(apiKey)
    }

    private func isRetryable(_ error: LiteLLMError) -> Bool {
        if case let .transport(statusCode, _) = error {
            return retryPolicy.retryableStatusCodes.contains(statusCode)
        }
        return error.isRetryable
    }

    private func shouldFallback(after error: LiteLLMError) -> Bool {
        switch error {
        case .transport, .provider:
            true
        case .unknownModelAlias, .invalidRequest, .decoding, .cancelled:
            false
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var apiKeyOverride: String? {
        self["api_key"]?.stringValue
            ?? self["apiKey"]?.stringValue
            ?? self["credential"]?.stringValue
    }
}
