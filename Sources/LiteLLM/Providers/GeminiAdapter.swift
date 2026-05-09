import Foundation

struct GeminiAdapter: ProviderAdapter {
    let baseURL: URL
    let apiKey: String?
    let model: String

    var providerName: String { "gemini" }

    func withAPIKey(_ apiKey: String) -> any ProviderAdapter {
        GeminiAdapter(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest {
        var body: [String: JSONValue] = [
            "contents": .array(request.messages.filter { $0.role != .system && $0.role != .developer }.map(geminiContentJSON)),
        ]
        let system = request.messages
            .filter { $0.role == .system || $0.role == .developer }
            .map { textFromContent($0.content) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty {
            body["system_instruction"] = .object(["parts": .array([.object(["text": .string(system)])])])
        }
        var generationConfig: [String: JSONValue] = [:]
        if let temperature = request.temperature {
            generationConfig["temperature"] = .number(temperature)
        }
        if let maxTokens = request.maxTokens {
            generationConfig["max_output_tokens"] = .number(Double(maxTokens))
        }
        if case .jsonObject? = request.responseFormat {
            generationConfig["response_mime_type"] = .string("application/json")
        }
        if case let .jsonSchema(_, schema, _)? = request.responseFormat {
            generationConfig["response_mime_type"] = .string("application/json")
            generationConfig["response_schema"] = schema
        }
        if !generationConfig.isEmpty {
            body["generation_config"] = .object(generationConfig)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array([
                .object(["function_declarations": .array(request.tools.map(geminiToolJSON))]),
            ])
        }
        body.mergeExtra(request.extraBody)

        guard let apiKey, !apiKey.isEmpty else {
            throw LiteLLMError.invalidRequest("Gemini API key is required")
        }
        var headers = commonHeaders(extra: request.extraHeaders)
        headers["x-goog-api-key"] = apiKey
        let endpoint = stream ? "v1beta/models/\(model):streamGenerateContent" : "v1beta/models/\(model):generateContent"
        return ProviderHTTPRequest(url: baseURL.appendingPath(endpoint), headers: headers, body: body, streamBody: stream)
    }

    func parseResponse(data: Data) throws -> ChatResponse {
        do {
            let envelope = try JSONCoding.decoder.decode(GeminiEnvelope.self, from: data)
            let candidate = envelope.candidates.first
            let parts = candidate?.content.parts ?? []
            let text = parts.compactMap(\.text).joined()
            let toolCalls = parts.compactMap { part -> ToolCall? in
                guard let call = part.functionCall else { return nil }
                let arguments = String(data: (try? JSONEncoder().encode(call.args)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                return ToolCall(name: call.name, arguments: arguments)
            }
            return ChatResponse(
                model: model,
                message: LLMMessage(role: .assistant, content: text.isEmpty ? nil : .text(text), toolCalls: toolCalls.isEmpty ? nil : toolCalls),
                finishReason: candidate?.finishReason,
                usage: envelope.usageMetadata?.normalized(),
                provider: providerName
            )
        } catch {
            throw LiteLLMError.decoding(error.localizedDescription)
        }
    }

    func parseStreamLine(_ line: String) throws -> [StreamEvent] {
        guard let payload = geminiStreamPayload(from: line) else { return [] }
        if payload.hasPrefix("[") {
            let envelopes = try JSONCoding.decoder.decode([GeminiEnvelope].self, from: Data(payload.utf8))
            return envelopes.flatMap(events)
        }
        let envelope = try JSONCoding.decoder.decode(GeminiEnvelope.self, from: Data(payload.utf8))
        return events(from: envelope)
    }

    private func events(from envelope: GeminiEnvelope) -> [StreamEvent] {
        var events: [StreamEvent] = []
        for part in envelope.candidates.first?.content.parts ?? [] {
            if let text = part.text, !text.isEmpty {
                events.append(.textDelta(text))
            }
            if let call = part.functionCall {
                let arguments = String(data: (try? JSONEncoder().encode(call.args)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                events.append(.toolCallDelta(ToolCall(name: call.name, arguments: arguments)))
            }
        }
        if envelope.candidates.first?.finishReason != nil {
            events.append(.done)
        }
        return events
    }
}

private func geminiStreamPayload(from line: String) -> String? {
    guard var payload = ssePayload(from: line) else { return nil }
    payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !payload.isEmpty, payload != "[" && payload != "]" else { return nil }
    if payload.hasSuffix(",") {
        payload.removeLast()
        payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard payload.hasPrefix("{") || payload.hasPrefix("[") else { return nil }
    return payload
}

private func geminiContentJSON(_ message: LLMMessage) -> JSONValue {
    let role = message.role == .assistant ? "model" : "user"
    var parts: [JSONValue] = []
    if message.role == .tool {
        let response = (try? JSONDecoder().decode(JSONValue.self, from: Data(textFromContent(message.content).utf8)))
            ?? .object(["content": .string(textFromContent(message.content))])
        return .object([
            "role": .string("user"),
            "parts": .array([
                .object([
                    "function_response": .object([
                        "name": .string(message.toolCallID ?? ""),
                        "response": response,
                    ]),
                ]),
            ]),
        ])
    }
    let text = textFromContent(message.content)
    if !text.isEmpty {
        parts.append(.object(["text": .string(text)]))
    }
    for toolCall in message.toolCalls ?? [] {
        let args = (try? JSONDecoder().decode(JSONValue.self, from: Data(toolCall.arguments.utf8))) ?? .object([:])
        parts.append(.object(["function_call": .object(["name": .string(toolCall.name), "args": args])]))
    }
    return .object(["role": .string(role), "parts": .array(parts)])
}

private func geminiToolJSON(_ tool: ToolDefinition) -> JSONValue {
    var object: [String: JSONValue] = [
        "name": .string(tool.name),
        "parameters": tool.parameters,
    ]
    if let description = tool.description {
        object["description"] = .string(description)
    }
    return .object(object)
}

struct GeminiEnvelope: Decodable {
    let candidates: [GeminiCandidate]
    let usageMetadata: GeminiUsage?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent
    let finishReason: String?
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]
}

struct GeminiPart: Decodable {
    let text: String?
    let functionCall: GeminiFunctionCall?
}

struct GeminiFunctionCall: Decodable {
    let name: String
    let args: JSONValue
}

struct GeminiUsage: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?

    func normalized() -> Usage {
        normalizedUsage(promptTokens: promptTokenCount, completionTokens: candidatesTokenCount, totalTokens: totalTokenCount)
    }
}
