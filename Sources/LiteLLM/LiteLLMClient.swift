import Foundation

public final class LiteLLMClient: Sendable {
    private let models: [ModelAlias: Provider]
    private let fallbackPolicy: FallbackPolicy
    private let retryPolicy: RetryPolicy
    private let transport: any HTTPTransport

    public convenience init(
        models: [ModelAlias: Provider],
        fallbacks: [String: [String]] = [:],
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.init(
            models: models,
            fallbackPolicy: FallbackPolicy(fallbacks),
            retryPolicy: retryPolicy,
            transport: URLSessionHTTPTransport()
        )
    }

    init(
        models: [ModelAlias: Provider],
        fallbackPolicy: FallbackPolicy,
        retryPolicy: RetryPolicy,
        transport: any HTTPTransport
    ) {
        self.models = models
        self.fallbackPolicy = fallbackPolicy
        self.retryPolicy = retryPolicy
        self.transport = transport
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
            Task {
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
        }
    }

    private func executeChat(model alias: ModelAlias, request: ChatRequest) async throws -> ChatResponse {
        let provider = try provider(for: alias)
        let adapter = provider.adapter()
        let providerRequest = try adapter.makeRequest(request, stream: false)
        let httpRequest = try makeHTTPRequest(providerRequest)

        var attempt = 0
        while true {
            if Task.isCancelled { throw LiteLLMError.cancelled }
            do {
                let (data, response) = try await transport.data(for: httpRequest)
                guard (200..<300).contains(response.statusCode) else {
                    throw LiteLLMError.transport(statusCode: response.statusCode, body: String(data: data, encoding: .utf8) ?? "")
                }
                return try adapter.parseResponse(data: data)
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
        let provider = try provider(for: alias)
        let adapter = provider.adapter()
        let providerRequest = try adapter.makeRequest(request, stream: true)
        let httpRequest = try makeHTTPRequest(providerRequest)
        let (bytes, response) = try await transport.bytes(for: httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw LiteLLMError.transport(statusCode: response.statusCode, body: "")
        }

        for try await line in bytes.lines {
            if Task.isCancelled { throw LiteLLMError.cancelled }
            for event in try adapter.parseStreamLine(line) {
                continuation.yield(event)
                if event == .done {
                    return
                }
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

    private func makeHTTPRequest(_ providerRequest: ProviderHTTPRequest) throws -> HTTPRequest {
        HTTPRequest(
            url: providerRequest.url,
            method: "POST",
            headers: providerRequest.headers,
            body: try JSONCoding.data(providerRequest.body)
        )
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
