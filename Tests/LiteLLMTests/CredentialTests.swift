import Foundation
import Testing
@testable import LiteLLM

@Suite("Credentials")
struct CredentialTests {
    @Test func apiKeyProviderSuppliesMissingProviderKey() async throws {
        let transport = MockHTTPTransport(responses: [(200, anthropicResponse("ok"))])
        let client = LiteLLMClient(
            models: [
                "smart": .anthropic(model: "claude"),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport,
            apiKeyProvider: { provider, alias in
                #expect(provider.providerName == "anthropic")
                #expect(alias == "smart")
                return "lazy-key"
            }
        )

        _ = try await client.chat(model: "smart", messages: [.user("Hello")])

        #expect(await transport.requests.first?.headers["x-api-key"] == "lazy-key")
    }

    @Test func perCallCredentialOverrideWinsOverConfiguredKey() async throws {
        let transport = MockHTTPTransport(responses: [(200, openAIResponse("ok"))])
        let client = LiteLLMClient(
            models: [
                "fast": .openAICompatible(
                    baseURL: URL(string: "https://api.openai.com")!,
                    apiKey: "configured-key",
                    model: "gpt"
                ),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        _ = try await client.chat(
            model: "fast",
            request: ChatRequest(
                messages: [.user("Hello")],
                providerOptions: ["api_key": "override-key"]
            )
        )

        #expect(await transport.requests.first?.headers["Authorization"] == "Bearer override-key")
    }

    @Test func missingRequiredProviderKeyThrowsInvalidRequest() async {
        let transport = MockHTTPTransport(responses: [(200, anthropicResponse("should not happen"))])
        let client = LiteLLMClient(
            models: [
                "smart": .anthropic(model: "claude"),
            ],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        await #expect(throws: LiteLLMError.invalidRequest("Anthropic API key is required")) {
            _ = try await client.chat(model: "smart", messages: [.user("Hello")])
        }
        #expect(await transport.requests.isEmpty)
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

    private func anthropicResponse(_ content: String) -> Data {
        Data("""
        {
          "id": "msg_1",
          "model": "claude",
          "content": [
            {"type": "text", "text": "\(content)"}
          ],
          "stop_reason": "end_turn"
        }
        """.utf8)
    }
}
