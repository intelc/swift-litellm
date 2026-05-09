import Foundation

struct OpenAICompatibleAdapter: ProviderAdapter {
    let baseURL: URL
    let apiKey: String?
    let model: String

    var providerName: String { "openai-compatible" }

    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(request.messages.map { openAIMessageJSON($0) }),
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(openAIToolJSON))
        }
        if stream {
            body["stream"] = .bool(true)
        }
        mergeCommonRequestFields(into: &body, request: request)

        var headers = commonHeaders(extra: request.extraHeaders)
        if let apiKey {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return ProviderHTTPRequest(url: baseURL.appendingPath("v1/chat/completions"), headers: headers, body: body, streamBody: stream)
    }

    func parseResponse(data: Data) throws -> ChatResponse {
        do {
            let envelope = try JSONCoding.decoder.decode(OpenAIChatEnvelope.self, from: data)
            guard let choice = envelope.choices.first else {
                throw LiteLLMError.decoding("OpenAI-compatible response had no choices")
            }
            return ChatResponse(
                id: envelope.id,
                model: envelope.model,
                message: choice.message.normalized(),
                finishReason: choice.finishReason,
                usage: envelope.usage?.normalized(),
                provider: providerName
            )
        } catch let error as LiteLLMError {
            throw error
        } catch {
            throw LiteLLMError.decoding(error.localizedDescription)
        }
    }

    func parseStreamLine(_ line: String) throws -> [StreamEvent] {
        guard let payload = ssePayload(from: line) else { return [] }
        if payload == "[DONE]" {
            return [.done]
        }
        let chunk = try JSONCoding.decoder.decode(OpenAIStreamChunk.self, from: Data(payload.utf8))
        guard let choice = chunk.choices.first else { return [] }
        var events: [StreamEvent] = []
        if let content = choice.delta.content, !content.isEmpty {
            events.append(.textDelta(content))
        }
        if let toolCalls = choice.delta.toolCalls {
            events.append(contentsOf: toolCalls.map { .toolCallDelta($0.normalized()) })
        }
        if choice.finishReason != nil {
            events.append(.done)
        }
        return events
    }
}

struct OpenAIChatEnvelope: Decodable {
    let id: String?
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Decodable {
    let message: OpenAIMessageWire
    let finishReason: String?
}

struct OpenAIMessageWire: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIToolCallWire]?

    func normalized() -> LLMMessage {
        let role = LLMMessage.Role(rawValue: role ?? "assistant") ?? .assistant
        return LLMMessage(role: role, content: content.map(LLMContent.text), toolCalls: toolCalls?.map { $0.normalized() })
    }
}

struct OpenAIToolCallWire: Decodable {
    let id: String?
    let function: OpenAIFunctionCallWire

    func normalized() -> ToolCall {
        ToolCall(id: id, name: function.name, arguments: function.arguments)
    }
}

struct OpenAIFunctionCallWire: Decodable {
    let name: String
    let arguments: String
}

struct OpenAIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    func normalized() -> Usage {
        Usage(promptTokens: promptTokens ?? 0, completionTokens: completionTokens ?? 0, totalTokens: totalTokens)
    }
}

struct OpenAIStreamChunk: Decodable {
    let choices: [OpenAIStreamChoice]
}

struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIStreamDelta
    let finishReason: String?
}

struct OpenAIStreamDelta: Decodable {
    let content: String?
    let toolCalls: [OpenAIToolCallWire]?
}
