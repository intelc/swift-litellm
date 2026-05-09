import Foundation
import Testing
@testable import LiteLLM

@Suite("Router")
struct RouterTests {
    @Test func aliasResolvesToConfiguredProvider() async throws {
        let transport = MockHTTPTransport(responses: [(200, openAIResponse("primary"))])
        let client = LiteLLMClient(
            models: [
                "fast": .openAICompatible(baseURL: URL(string: "https://openrouter.ai/api")!, apiKey: "key", model: "openai/gpt-4o-mini"),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "fast", messages: [.user("Hello")])

        #expect(response.message.content == .text("primary"))
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.url.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test func fallbackChainTriesNextModelOnRetryableError() async throws {
        let transport = MockHTTPTransport(responses: [
            (500, Data("upstream down".utf8)),
            (200, ollamaResponse("local")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        let response = try await client.chat(model: "smart", messages: [.user("Hello")])

        #expect(response.message.content == .text("local"))
        #expect(await transport.requests.map(\.url.path) == ["/v1/chat/completions", "/api/chat"])
    }

    @Test func nonRetryableDecodingErrorDoesNotFallback() async throws {
        let transport = MockHTTPTransport(responses: [
            (200, Data("{\"not\":\"a chat response\"}".utf8)),
            (200, ollamaResponse("should not happen")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        await #expect(throws: LiteLLMError.self) {
            _ = try await client.chat(model: "smart", messages: [.user("Hello")])
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func retryHappensBeforeFallback() async throws {
        let transport = MockHTTPTransport(responses: [
            (500, Data("first failure".utf8)),
            (200, openAIResponse("retried")),
        ])
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 1),
            transport: transport
        )

        let response = try await client.chat(model: "smart", messages: [.user("Hello")])

        #expect(response.message.content == .text("retried"))
        #expect(await transport.requests.map(\.url.path) == ["/v1/chat/completions", "/v1/chat/completions"])
    }

    @Test func cancellationDoesNotContinueFallbacks() async {
        let client = LiteLLMClient(
            models: [
                "smart": .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
                "local": .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama3.2"),
            ],
            fallbackPolicy: FallbackPolicy(["smart": ["local"]]),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: SlowHTTPTransport()
        )

        let task = Task {
            try await client.chat(model: "smart", messages: [.user("Hello")])
        }
        task.cancel()

        await #expect(throws: LiteLLMError.cancelled) {
            _ = try await task.value
        }
    }

    private func openAIResponse(_ content: String) -> Data {
        Data("""
        {
          "id": "chatcmpl_1",
          "model": "gpt",
          "choices": [{
            "message": {"role": "assistant", "content": "\(content)"},
            "finish_reason": "stop"
          }]
        }
        """.utf8)
    }

    private func ollamaResponse(_ content: String) -> Data {
        Data("""
        {
          "model": "llama3.2",
          "message": {"role": "assistant", "content": "\(content)"},
          "done": true
        }
        """.utf8)
    }
}
