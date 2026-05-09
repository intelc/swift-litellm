import Foundation
import Testing
@testable import LiteLLM

@Suite("Provider errors")
struct ProviderErrorTests {
    @Test func openAIErrorBodyIsNormalized() async throws {
        let error = try await transportErrorBody(
            provider: .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
            body: """
            {
              "error": {
                "message": "The request is missing a required parameter.",
                "type": "invalid_request_error",
                "code": "missing_required_parameter"
              }
            }
            """
        )

        #expect(error == "openai-compatible invalid_request_error missing_required_parameter: The request is missing a required parameter.")
    }

    @Test func anthropicErrorBodyIsNormalized() async throws {
        let error = try await transportErrorBody(
            provider: .anthropic(apiKey: "key", model: "claude"),
            body: """
            {
              "type": "error",
              "error": {
                "type": "invalid_request_error",
                "message": "max_tokens is required"
              }
            }
            """
        )

        #expect(error == "anthropic invalid_request_error: max_tokens is required")
    }

    @Test func geminiErrorBodyIsNormalized() async throws {
        let error = try await transportErrorBody(
            provider: .gemini(apiKey: "key", model: "gemini"),
            body: """
            {
              "error": {
                "code": 400,
                "message": "API key not valid.",
                "status": "INVALID_ARGUMENT"
              }
            }
            """
        )

        #expect(error == "gemini INVALID_ARGUMENT 400: API key not valid.")
    }

    @Test func ollamaErrorBodyIsNormalized() async throws {
        let error = try await transportErrorBody(
            provider: .ollama(baseURL: URL(string: "http://localhost:11434")!, model: "llama"),
            body: """
            {
              "error": "model 'llama' not found"
            }
            """
        )

        #expect(error == "ollama: model 'llama' not found")
    }

    @Test func unstructuredErrorBodyIsPreserved() async throws {
        let error = try await transportErrorBody(
            provider: .openAICompatible(baseURL: URL(string: "https://api.openai.com")!, apiKey: "key", model: "gpt"),
            body: "upstream down"
        )

        #expect(error == "upstream down")
    }

    private func transportErrorBody(provider: Provider, body: String) async throws -> String {
        let transport = MockHTTPTransport(responses: [(400, Data(body.utf8))])
        let client = LiteLLMClient(
            models: ["bad": provider],
            fallbackPolicy: FallbackPolicy(),
            retryPolicy: RetryPolicy(maxRetries: 0),
            transport: transport
        )

        do {
            _ = try await client.chat(model: "bad", messages: [.user("Hello")])
        } catch let LiteLLMError.transport(_, body) {
            return body
        }

        Issue.record("Expected transport error")
        return ""
    }
}
