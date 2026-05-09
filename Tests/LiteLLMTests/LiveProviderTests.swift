import Foundation
import Testing
@testable import LiteLLM

@Suite("Live providers")
struct LiveProviderTests {
    @Test func openAICompatibleLiveChatWhenConfigured() async throws {
        guard let apiKey = env("OPENAI_API_KEY") else { return }
        let client = LiteLLMClient(
            models: [
                "live": .openAICompatible(
                    baseURL: URL(string: env("OPENAI_BASE_URL") ?? "https://api.openai.com")!,
                    apiKey: apiKey,
                    model: env("OPENAI_MODEL") ?? "gpt-4o-mini"
                ),
            ],
            retryPolicy: RetryPolicy(maxRetries: 0)
        )

        let response = try await client.chat(model: "live", messages: [.user("Reply with exactly: ok")], maxTokens: 8)

        #expect(response.provider == "openai-compatible")
        #expect(response.message.content != nil || response.message.toolCalls != nil)
    }

    @Test func anthropicLiveChatWhenConfigured() async throws {
        guard let apiKey = env("ANTHROPIC_API_KEY") else { return }
        let client = LiteLLMClient(
            models: [
                "live": .anthropic(
                    apiKey: apiKey,
                    model: env("ANTHROPIC_MODEL") ?? "claude-3-5-haiku-latest"
                ),
            ],
            retryPolicy: RetryPolicy(maxRetries: 0)
        )

        let response = try await client.chat(model: "live", messages: [.user("Reply with exactly: ok")], maxTokens: 8)

        #expect(response.provider == "anthropic")
        #expect(response.message.content != nil || response.message.toolCalls != nil)
    }

    @Test func geminiLiveChatWhenConfigured() async throws {
        guard let apiKey = env("GEMINI_API_KEY") else { return }
        let client = LiteLLMClient(
            models: [
                "live": .gemini(
                    apiKey: apiKey,
                    model: env("GEMINI_MODEL") ?? "gemini-2.0-flash"
                ),
            ],
            retryPolicy: RetryPolicy(maxRetries: 0)
        )

        let response = try await client.chat(model: "live", messages: [.user("Reply with exactly: ok")], maxTokens: 8)

        #expect(response.provider == "gemini")
        #expect(response.message.content != nil || response.message.toolCalls != nil)
    }

    @Test func ollamaLiveChatWhenConfigured() async throws {
        guard let baseURLString = env("OLLAMA_BASE_URL"), let baseURL = URL(string: baseURLString) else { return }
        let client = LiteLLMClient(
            models: [
                "live": .ollama(
                    baseURL: baseURL,
                    model: env("OLLAMA_MODEL") ?? "llama3.2"
                ),
            ],
            retryPolicy: RetryPolicy(maxRetries: 0)
        )

        let response = try await client.chat(model: "live", messages: [.user("Reply with exactly: ok")], maxTokens: 8)

        #expect(response.provider == "ollama")
        #expect(response.message.content != nil || response.message.toolCalls != nil)
    }

    private func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return value?.isEmpty == false ? value : nil
    }
}
