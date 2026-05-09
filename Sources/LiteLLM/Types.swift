import Foundation

public struct LLMMessage: Codable, Equatable, Sendable {
    public var role: Role
    public var content: LLMContent?
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?

    public init(role: Role, content: LLMContent? = nil, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ text: String) -> LLMMessage {
        LLMMessage(role: .system, content: .text(text))
    }

    public static func developer(_ text: String) -> LLMMessage {
        LLMMessage(role: .developer, content: .text(text))
    }

    public static func user(_ text: String) -> LLMMessage {
        LLMMessage(role: .user, content: .text(text))
    }

    public static func assistant(_ text: String) -> LLMMessage {
        LLMMessage(role: .assistant, content: .text(text))
    }

    public enum Role: String, Codable, Sendable {
        case system
        case developer
        case user
        case assistant
        case tool
    }
}

public enum LLMContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([LLMContentPart])

    public var textValue: String? {
        if case let .text(text) = self { text } else { nil }
    }
}

public enum LLMContentPart: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            if let object = try? container.decode([String: String].self, forKey: .imageURL),
               let url = object["url"] {
                self = .imageURL(url)
            } else {
                self = .imageURL(try container.decode(String.self, forKey: .imageURL))
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported content part type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": url], forKey: .imageURL)
        }
    }
}

public struct ChatRequest: Codable, Equatable, Sendable {
    public var messages: [LLMMessage]
    public var tools: [ToolDefinition]
    public var temperature: Double?
    public var maxTokens: Int?
    public var responseFormat: ResponseFormat?
    public var extraHeaders: [String: String]
    public var extraBody: [String: JSONValue]
    public var providerOptions: [String: JSONValue]

    public init(
        messages: [LLMMessage],
        tools: [ToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        responseFormat: ResponseFormat? = nil,
        extraHeaders: [String: String] = [:],
        extraBody: [String: JSONValue] = [:],
        providerOptions: [String: JSONValue] = [:]
    ) {
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.responseFormat = responseFormat
        self.extraHeaders = extraHeaders
        self.extraBody = extraBody
        self.providerOptions = providerOptions
    }
}

public enum ResponseFormat: Codable, Equatable, Sendable {
    case text
    case jsonObject
    case jsonSchema(name: String, schema: JSONValue, strict: Bool)
}

public struct ChatResponse: Codable, Equatable, Sendable {
    public var id: String?
    public var model: String
    public var message: LLMMessage
    public var finishReason: String?
    public var usage: Usage?
    public var provider: String

    public init(id: String? = nil, model: String, message: LLMMessage, finishReason: String? = nil, usage: Usage? = nil, provider: String) {
        self.id = id
        self.model = model
        self.message = message
        self.finishReason = finishReason
        self.usage = usage
        self.provider = provider
    }
}

public enum StreamEvent: Equatable, Sendable {
    case textDelta(String)
    case toolCallDelta(ToolCall)
    case messageCompleted(ChatResponse)
    case done
}

public struct ToolDefinition: Codable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var parameters: JSONValue

    public init(name: String, description: String? = nil, parameters: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var arguments: String

    public init(id: String? = nil, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct Usage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? promptTokens + completionTokens
    }
}

public struct RetryPolicy: Codable, Equatable, Sendable {
    public var maxRetries: Int
    public var retryableStatusCodes: Set<Int>

    public init(maxRetries: Int = 1, retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]) {
        self.maxRetries = maxRetries
        self.retryableStatusCodes = retryableStatusCodes
    }
}

public struct FallbackPolicy: Codable, Equatable, Sendable {
    public var fallbacks: [String: [String]]

    public init(_ fallbacks: [String: [String]] = [:]) {
        self.fallbacks = fallbacks
    }
}

public typealias ModelAlias = String
