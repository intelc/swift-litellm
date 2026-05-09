import Foundation

func mergeCommonRequestFields(into body: inout [String: JSONValue], request: ChatRequest, maxTokenKey: String = "max_tokens") {
    if let temperature = request.temperature {
        body["temperature"] = .number(temperature)
    }
    if let maxTokens = request.maxTokens {
        body[maxTokenKey] = .number(Double(maxTokens))
    }
    if let responseFormat = request.responseFormat {
        body["response_format"] = responseFormat.jsonValue
    }
    body.mergeExtra(request.extraBody)
}

func openAIMessageJSON(_ message: LLMMessage, mapDeveloperToSystem: Bool = false) -> JSONValue {
    var object: [String: JSONValue] = [
        "role": .string(mapDeveloperToSystem && message.role == .developer ? "system" : message.role.rawValue)
    ]
    if let content = message.content {
        object["content"] = openAIContentJSON(content)
    }
    if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
        object["tool_calls"] = .array(toolCalls.map(openAIToolCallJSON))
    }
    if let toolCallID = message.toolCallID {
        object["tool_call_id"] = .string(toolCallID)
    }
    return .object(object)
}

func openAIContentJSON(_ content: LLMContent) -> JSONValue {
    switch content {
    case let .text(text):
        .string(text)
    case let .parts(parts):
        .array(parts.map { part in
            switch part {
            case let .text(text):
                .object(["type": .string("text"), "text": .string(text)])
            case let .imageURL(url):
                .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
            }
        })
    }
}

func openAIToolJSON(_ tool: ToolDefinition) -> JSONValue {
    .object([
        "type": .string("function"),
        "function": .object([
            "name": .string(tool.name),
            "description": tool.description.map(JSONValue.string) ?? .null,
            "parameters": tool.parameters,
        ]),
    ])
}

func openAIToolCallJSON(_ toolCall: ToolCall) -> JSONValue {
    var object: [String: JSONValue] = [
        "type": .string("function"),
        "function": .object([
            "name": .string(toolCall.name),
            "arguments": .string(toolCall.arguments),
        ]),
    ]
    if let id = toolCall.id {
        object["id"] = .string(id)
    }
    return .object(object)
}

func textFromContent(_ content: LLMContent?) -> String {
    guard let content else { return "" }
    switch content {
    case let .text(text):
        return text
    case let .parts(parts):
        return parts.compactMap { part in
            if case let .text(text) = part { text } else { nil }
        }.joined(separator: "\n")
    }
}

func commonHeaders(contentType: String = "application/json", extra: [String: String]) -> [String: String] {
    var headers = ["Content-Type": contentType]
    for (key, value) in extra {
        headers[key] = value
    }
    return headers
}

func normalizedUsage(promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) -> Usage {
    var prompt = promptTokens
    var completion = completionTokens
    if let totalTokens {
        if prompt == nil, let completion {
            prompt = max(0, totalTokens - completion)
        }
        if completion == nil, let prompt {
            completion = max(0, totalTokens - prompt)
        }
    }
    return Usage(promptTokens: prompt ?? 0, completionTokens: completion ?? 0, totalTokens: totalTokens)
}

func ssePayload(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("data:") {
        return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
    return trimmed
}

extension ResponseFormat {
    var jsonValue: JSONValue {
        switch self {
        case .text:
            .object(["type": .string("text")])
        case .jsonObject:
            .object(["type": .string("json_object")])
        case let .jsonSchema(name, schema, strict):
            .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string(name),
                    "schema": schema,
                    "strict": .bool(strict),
                ]),
            ])
        }
    }
}

extension URL {
    func appendingPath(_ path: String) -> URL {
        var result = self
        for component in path.split(separator: "/") {
            result.appendPathComponent(String(component))
        }
        return result
    }
}
