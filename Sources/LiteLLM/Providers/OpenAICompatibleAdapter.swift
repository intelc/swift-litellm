import Foundation

struct OpenAICompatibleAdapter: ProviderAdapter {
    let baseURL: URL
    let apiKey: String?
    let model: String
    let providerName: String

    init(baseURL: URL, apiKey: String?, model: String, providerName: String = "openai-compatible") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerName = providerName
    }

    func withAPIKey(_ apiKey: String) -> any ProviderAdapter {
        OpenAICompatibleAdapter(baseURL: baseURL, apiKey: apiKey, model: model, providerName: providerName)
    }

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
    let index: Int?
    let function: OpenAIFunctionCallWire?

    func normalized() -> ToolCall {
        ToolCall(id: id, name: function?.name ?? "", arguments: function?.arguments ?? "")
    }
}

struct OpenAIFunctionCallWire: Decodable, Equatable {
    let name: String?
    let arguments: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        if let stringArguments = try? container.decodeIfPresent(String.self, forKey: .arguments) {
            arguments = stringArguments
        } else if let jsonArguments = try? container.decodeIfPresent(JSONValue.self, forKey: .arguments) {
            arguments = String(data: (try? JSONEncoder().encode(jsonArguments)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        } else {
            arguments = nil
        }
    }
}

struct OpenAIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    func normalized() -> Usage {
        normalizedUsage(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens)
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
