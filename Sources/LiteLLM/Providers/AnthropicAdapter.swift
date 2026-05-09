import Foundation

struct AnthropicAdapter: ProviderAdapter {
    let baseURL: URL
    let apiKey: String
    let model: String

    var providerName: String { "anthropic" }

    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest {
        let system = request.messages
            .filter { $0.role == .system || $0.role == .developer }
            .map { textFromContent($0.content) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let messages = request.messages
            .filter { $0.role != .system && $0.role != .developer }
            .map(anthropicMessageJSON)

        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(messages),
            "max_tokens": .number(Double(request.maxTokens ?? 1024)),
        ]
        if !system.isEmpty {
            body["system"] = .string(system)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map(anthropicToolJSON))
        }
        if stream {
            body["stream"] = .bool(true)
        }
        if let temperature = request.temperature {
            body["temperature"] = .number(temperature)
        }
        if let responseFormat = request.responseFormat {
            body["response_format"] = responseFormat.jsonValue
        }
        body.mergeExtra(request.extraBody)

        var headers = commonHeaders(extra: request.extraHeaders)
        headers["x-api-key"] = apiKey
        headers["anthropic-version"] = "2023-06-01"
        return ProviderHTTPRequest(url: baseURL.appendingPath("v1/messages"), headers: headers, body: body, streamBody: stream)
    }

    func parseResponse(data: Data) throws -> ChatResponse {
        do {
            let envelope = try JSONCoding.decoder.decode(AnthropicMessageEnvelope.self, from: data)
            var text = ""
            var toolCalls: [ToolCall] = []
            for block in envelope.content {
                switch block {
                case let .text(value):
                    text += value
                case let .toolUse(id, name, input):
                    let arguments = String(data: try JSONEncoder().encode(input), encoding: .utf8) ?? "{}"
                    toolCalls.append(ToolCall(id: id, name: name, arguments: arguments))
                }
            }
            return ChatResponse(
                id: envelope.id,
                model: envelope.model,
                message: LLMMessage(role: .assistant, content: text.isEmpty ? nil : .text(text), toolCalls: toolCalls.isEmpty ? nil : toolCalls),
                finishReason: envelope.stopReason,
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
        guard let payload = ssePayload(from: line), payload.hasPrefix("{") else { return [] }
        let event = try JSONCoding.decoder.decode(AnthropicStreamEnvelope.self, from: Data(payload.utf8))
        switch event.type {
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text {
                return [.textDelta(text)]
            }
            if event.delta?.type == "input_json_delta", let partial = event.delta?.partialJson {
                return [.toolCallDelta(ToolCall(id: event.contentBlock?.id, name: event.contentBlock?.name ?? "", arguments: partial))]
            }
            return []
        case "content_block_start":
            if event.contentBlock?.type == "tool_use", let name = event.contentBlock?.name {
                return [.toolCallDelta(ToolCall(id: event.contentBlock?.id, name: name, arguments: "{}"))]
            }
            return []
        case "message_stop":
            return [.done]
        default:
            return []
        }
    }
}

private func anthropicMessageJSON(_ message: LLMMessage) -> JSONValue {
    switch message.role {
    case .tool:
        return .object([
            "role": .string("user"),
            "content": .array([
                .object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(message.toolCallID ?? ""),
                    "content": .string(textFromContent(message.content)),
                ]),
            ]),
        ])
    case .assistant:
        var contentBlocks: [JSONValue] = []
        let text = textFromContent(message.content)
        if !text.isEmpty {
            contentBlocks.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        for toolCall in message.toolCalls ?? [] {
            let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(toolCall.arguments.utf8))) ?? .object([:])
            contentBlocks.append(.object([
                "type": .string("tool_use"),
                "id": .string(toolCall.id ?? UUID().uuidString),
                "name": .string(toolCall.name),
                "input": input,
            ]))
        }
        return .object(["role": .string("assistant"), "content": .array(contentBlocks)])
    default:
        return .object([
            "role": .string("user"),
            "content": .string(textFromContent(message.content)),
        ])
    }
}

private func anthropicToolJSON(_ tool: ToolDefinition) -> JSONValue {
    var object: [String: JSONValue] = [
        "name": .string(tool.name),
        "input_schema": tool.parameters,
    ]
    if let description = tool.description {
        object["description"] = .string(description)
    }
    return .object(object)
}

struct AnthropicMessageEnvelope: Decodable {
    let id: String?
    let model: String
    let content: [AnthropicContentBlock]
    let stopReason: String?
    let usage: AnthropicUsage?
}

enum AnthropicContentBlock: Decodable {
    case text(String)
    case toolUse(id: String?, name: String, input: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:])
            )
        default:
            self = .text("")
        }
    }
}

struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    func normalized() -> Usage {
        let prompt = (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
        return Usage(promptTokens: prompt, completionTokens: outputTokens ?? 0)
    }
}

struct AnthropicStreamEnvelope: Decodable {
    let type: String
    let delta: AnthropicStreamDelta?
    let contentBlock: AnthropicStreamContentBlock?
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let partialJson: String?
}

struct AnthropicStreamContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
}
