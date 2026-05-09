import Foundation

public enum Provider: Equatable, Sendable {
    case openAICompatible(baseURL: URL, apiKey: String?, model: String)
    case anthropic(baseURL: URL = URL(string: "https://api.anthropic.com")!, apiKey: String, model: String)
    case gemini(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!, apiKey: String, model: String)
    case ollama(baseURL: URL = URL(string: "http://localhost:11434")!, model: String)

    public var model: String {
        switch self {
        case let .openAICompatible(_, _, model),
             let .anthropic(_, _, model),
             let .gemini(_, _, model),
             let .ollama(_, model):
            model
        }
    }

    public var providerName: String {
        switch self {
        case .openAICompatible: "openai-compatible"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        case .ollama: "ollama"
        }
    }
}

struct ProviderHTTPRequest: Equatable, Sendable {
    var url: URL
    var headers: [String: String]
    var body: [String: JSONValue]
    var streamBody: Bool
}

protocol ProviderAdapter: Sendable {
    var providerName: String { get }
    var model: String { get }
    func makeRequest(_ request: ChatRequest, stream: Bool) throws -> ProviderHTTPRequest
    func parseResponse(data: Data) throws -> ChatResponse
    func parseStreamLine(_ line: String) throws -> [StreamEvent]
}

extension Provider {
    func adapter() -> ProviderAdapter {
        switch self {
        case let .openAICompatible(baseURL, apiKey, model):
            OpenAICompatibleAdapter(baseURL: baseURL, apiKey: apiKey, model: model)
        case let .anthropic(baseURL, apiKey, model):
            AnthropicAdapter(baseURL: baseURL, apiKey: apiKey, model: model)
        case let .gemini(baseURL, apiKey, model):
            GeminiAdapter(baseURL: baseURL, apiKey: apiKey, model: model)
        case let .ollama(baseURL, model):
            OllamaAdapter(baseURL: baseURL, model: model)
        }
    }
}
