import Foundation
import Testing
@testable import LiteLLM

@Suite("Provider transforms")
struct ProviderTransformTests {
    @Test func openAICompatibleRequestMatchesFixture() throws {
        let adapter = OpenAICompatibleAdapter(
            baseURL: URL(string: "https://openrouter.ai/api")!,
            apiKey: "test-key",
            model: "openai/gpt-4o-mini"
        )
        let request = ChatRequest(messages: [.user("Hello")], temperature: 0.2)

        let providerRequest = try adapter.makeRequest(request, stream: true)

        #expect(providerRequest.url.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(providerRequest.headers["Authorization"] == "Bearer test-key")
        #expect(try bodyJSON(providerRequest) == decodedFixture("openai_basic_request"))
    }

    @Test func anthropicRequestMapsSystemDeveloperAndTools() throws {
        let adapter = AnthropicAdapter(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "anthropic-key",
            model: "claude-sonnet-4-5"
        )
        let request = ChatRequest(
            messages: [.system("Be concise."), .user("Hello")],
            maxTokens: 128
        )

        let providerRequest = try adapter.makeRequest(request, stream: false)

        #expect(providerRequest.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(providerRequest.headers["x-api-key"] == "anthropic-key")
        #expect(providerRequest.headers["anthropic-version"] == "2023-06-01")
        #expect(try bodyJSON(providerRequest) == decodedFixture("anthropic_basic_request"))
    }

    @Test func anthropicRequestMapsToolConversation() throws {
        let adapter = AnthropicAdapter(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "anthropic-key",
            model: "claude-sonnet-4-5"
        )
        let request = ChatRequest(
            messages: [
                .user("Weather?"),
                LLMMessage(
                    role: .assistant,
                    toolCalls: [ToolCall(id: "toolu_1", name: "get_weather", arguments: "{\"city\":\"SF\"}")]
                ),
                LLMMessage(role: .tool, content: .text("{\"temp\":58}"), toolCallID: "toolu_1"),
            ],
            tools: [weatherTool]
        )

        let providerRequest = try adapter.makeRequest(request, stream: false)

        #expect(try bodyJSON(providerRequest) == decodedFixture("anthropic_tool_request"))
    }

    @Test func geminiRequestMapsSystemAndGenerationConfig() throws {
        let adapter = GeminiAdapter(
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            apiKey: "gemini-key",
            model: "gemini-2.5-pro"
        )
        let request = ChatRequest(
            messages: [.developer("Be crisp."), .user("Hello")],
            temperature: 0.3,
            maxTokens: 64,
            responseFormat: .jsonObject,
            extraBody: ["cached_content": "abc"]
        )

        let providerRequest = try adapter.makeRequest(request, stream: false)

        #expect(providerRequest.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent")
        #expect(providerRequest.headers["x-goog-api-key"] == "gemini-key")
        guard case let .object(body) = try bodyJSON(providerRequest) else {
            Issue.record("Expected object body")
            return
        }
        #expect(body["cached_content"] == "abc")
        #expect(body["system_instruction"] != nil)
        #expect(body["generation_config"] != nil)
    }

    @Test func geminiRequestMapsToolConversationAndJsonSchema() throws {
        let adapter = GeminiAdapter(
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            apiKey: "gemini-key",
            model: "gemini-2.5-pro"
        )
        let request = ChatRequest(
            messages: [
                .user("Weather?"),
                LLMMessage(
                    role: .assistant,
                    toolCalls: [ToolCall(name: "get_weather", arguments: "{\"city\":\"SF\"}")]
                ),
                LLMMessage(role: .tool, content: .text("{\"temp\":58}"), toolCallID: "get_weather"),
            ],
            tools: [weatherTool],
            responseFormat: .jsonSchema(
                name: "weather_answer",
                schema: ["type": "object", "properties": ["answer": ["type": "string"]]],
                strict: true
            )
        )

        let providerRequest = try adapter.makeRequest(request, stream: false)

        #expect(try bodyJSON(providerRequest) == decodedFixture("gemini_tool_request"))
    }

    @Test func ollamaRequestMapsDeveloperToSystemAndJsonMode() throws {
        let adapter = OllamaAdapter(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2"
        )
        let request = ChatRequest(
            messages: [.developer("Be concise."), .user("Hello")],
            temperature: 0.4,
            responseFormat: .jsonObject
        )

        let providerRequest = try adapter.makeRequest(request, stream: true)

        #expect(providerRequest.url.absoluteString == "http://localhost:11434/api/chat")
        guard case let .object(body) = try bodyJSON(providerRequest) else {
            Issue.record("Expected object body")
            return
        }
        #expect(body["model"] == "llama3.2")
        #expect(body["stream"] == true)
        #expect(body["format"] == "json")
    }

    @Test func ollamaRequestMapsToolConversation() throws {
        let adapter = OllamaAdapter(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2"
        )
        let request = ChatRequest(
            messages: [
                .developer("Be concise."),
                .user("Weather?"),
                LLMMessage(
                    role: .assistant,
                    toolCalls: [ToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\":\"SF\"}")]
                ),
                LLMMessage(role: .tool, content: .text("{\"temp\":58}"), toolCallID: "call_1"),
            ],
            tools: [weatherTool],
            temperature: 0.1,
            maxTokens: 32
        )

        let providerRequest = try adapter.makeRequest(request, stream: false)

        #expect(providerRequest.url.absoluteString == "http://localhost:11434/api/chat")
        #expect(try bodyJSON(providerRequest) == decodedFixture("ollama_tool_request"))
    }

    private var weatherTool: ToolDefinition {
        ToolDefinition(
            name: "get_weather",
            description: "Get weather for a city.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string"],
                ],
                "required": ["city"],
            ]
        )
    }
}
