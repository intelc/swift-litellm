import Foundation

public struct ChatStreamAccumulator: Sendable {
    private var text = ""
    private var toolCalls: [ToolCall] = []
    private var completedResponse: ChatResponse?

    public init() {}

    public mutating func append(_ event: StreamEvent, model: String = "", provider: String = "stream") -> ChatResponse? {
        switch event {
        case let .textDelta(delta):
            text += delta
            return nil
        case let .toolCallDelta(delta):
            merge(delta)
            return nil
        case let .messageCompleted(response):
            completedResponse = response
            return response
        case .done:
            return response(model: model, provider: provider)
        }
    }

    public func response(model: String = "", provider: String = "stream") -> ChatResponse {
        if let completedResponse {
            return completedResponse
        }
        return ChatResponse(
            model: model,
            message: LLMMessage(
                role: .assistant,
                content: text.isEmpty ? nil : .text(text),
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            ),
            provider: provider
        )
    }

    private mutating func merge(_ delta: ToolCall) {
        let existingIndex = toolCalls.firstIndex { existing in
            if let id = delta.id, let existingID = existing.id {
                return id == existingID
            }
            if !delta.name.isEmpty, !existing.name.isEmpty {
                return delta.name == existing.name
            }
            return delta.name.isEmpty && delta.id == nil
        } ?? (delta.name.isEmpty && delta.id == nil ? toolCalls.indices.last : nil)

        let argumentDelta = delta.arguments == "{}" ? "" : delta.arguments
        guard let existingIndex else {
            toolCalls.append(ToolCall(id: delta.id, name: delta.name, arguments: argumentDelta))
            return
        }

        var existing = toolCalls[existingIndex]
        if existing.id == nil {
            existing.id = delta.id
        }
        if existing.name.isEmpty {
            existing.name = delta.name
        }
        existing.arguments += argumentDelta
        toolCalls[existingIndex] = existing
    }
}

public func collectChatResponse<S: AsyncSequence>(
    from stream: S,
    model: String = "",
    provider: String = "stream"
) async throws -> ChatResponse where S.Element == StreamEvent {
    var accumulator = ChatStreamAccumulator()
    for try await event in stream {
        if let response = accumulator.append(event, model: model, provider: provider) {
            return response
        }
    }
    return accumulator.response(model: model, provider: provider)
}
