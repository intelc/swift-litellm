import Foundation

struct OllamaAdapter: ProviderAdapter {
    let baseURL: URL
    let model: String

    var providerName: String { "ollama" }
    var apiKey: String? { nil }

    func withAPIKey(_ apiKey: String) -> any ProviderAdapter {
        self
    }

    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(request.messages.map { openAIMessageJSON($0, mapDeveloperToSystem: true) }),
            "stream": .bool(stream),
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(openAIToolJSON))
        }
        if let responseFormat = request.responseFormat {
            switch responseFormat {
            case .jsonObject, .jsonSchema:
                body["format"] = .string("json")
            case .text:
                break
            }
        }
        var options: [String: JSONValue] = [:]
        if let temperature = request.temperature {
            options["temperature"] = .number(temperature)
        }
        if let maxTokens = request.maxTokens {
            options["num_predict"] = .number(Double(maxTokens))
        }
        if !options.isEmpty {
            body["options"] = .object(options)
        }
        body.mergeExtra(request.extraBody)
        return ProviderHTTPRequest(url: baseURL.appendingPath("api/chat"), headers: commonHeaders(extra: request.extraHeaders), body: body, streamBody: stream)
    }

    func parseResponse(data: Data) throws -> ChatResponse {
        do {
            let envelope = try JSONCoding.decoder.decode(OllamaEnvelope.self, from: data)
            return ChatResponse(
                model: envelope.model ?? model,
                message: envelope.message?.normalized() ?? LLMMessage(role: .assistant),
                finishReason: envelope.done == true ? "stop" : nil,
                usage: envelope.normalizedUsage(),
                provider: providerName
            )
        } catch {
            throw LiteLLMError.decoding(error.localizedDescription)
        }
    }

    func parseStreamLine(_ line: String) throws -> [StreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let envelope = try JSONCoding.decoder.decode(OllamaEnvelope.self, from: Data(trimmed.utf8))
        if envelope.done == true {
            return [.done]
        }
        if let content = envelope.message?.content, !content.isEmpty {
            return [.textDelta(content)]
        }
        if let toolCalls = envelope.message?.toolCalls {
            return toolCalls.map { .toolCallDelta($0.normalized()) }
        }
        return []
    }
}

struct OllamaEnvelope: Decodable {
    let model: String?
    let message: OllamaMessage?
    let done: Bool?
    let promptEvalCount: Int?
    let evalCount: Int?

    func normalizedUsage() -> Usage? {
        guard promptEvalCount != nil || evalCount != nil else { return nil }
        return Usage(promptTokens: promptEvalCount ?? 0, completionTokens: evalCount ?? 0)
    }
}

struct OllamaMessage: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIToolCallWire]?

    func normalized() -> LLMMessage {
        LLMMessage(
            role: LLMMessage.Role(rawValue: role ?? "assistant") ?? .assistant,
            content: content?.isEmpty == false ? content.map(LLMContent.text) : nil,
            toolCalls: toolCalls?.map { $0.normalized() }
        )
    }
}
