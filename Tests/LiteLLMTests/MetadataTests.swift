import Foundation
import Testing
@testable import LiteLLM

@Suite("LiteLLM metadata")
struct MetadataTests {
    @Test func upstreamCommitIsRecorded() {
        #expect(ModelMetadata.upstream?.source != nil)
        #expect(ModelMetadata.upstream?.commit != nil || ModelMetadata.upstream?.ref != nil)
    }

    @Test func commonModelMetadataLoads() {
        let info = ModelMetadata.info(for: "gpt-4o-mini")
            ?? ModelMetadata.info(for: "openai/gpt-4o-mini")
            ?? ModelMetadata.info(for: "azure/eu/gpt-4o-mini-2024-07-18")

        #expect(info != nil)
        #expect(info?.litellmProvider != nil)
        #expect(info?.mode != nil)
        #expect((info?.maxInputTokens ?? 0) > 0)
    }

    @Test func capabilityHelpersReadModelMetadata() {
        let model = ["gpt-4o-mini", "openai/gpt-4o-mini", "azure/eu/gpt-4o-mini-2024-07-18"]
            .first { ModelMetadata.info(for: $0) != nil }

        guard let model else {
            Issue.record("Expected a common GPT-4o mini metadata entry")
            return
        }

        #expect(ModelMetadata.supports(.tools, model: model) == (ModelMetadata.info(for: model)?.supportsFunctionCalling == true))
        #expect(ModelMetadata.supports(.vision, model: model) == (ModelMetadata.info(for: model)?.supportsVision == true))
        #expect(ModelMetadata.supports(.tools, model: "definitely-not-a-real-model") == false)
    }

    @Test func clientCapabilityHelperResolvesAliasProviderModel() {
        let client = LiteLLMClient(
            models: [
                "fast": .openAICompatible(
                    baseURL: URL(string: "https://api.openai.com")!,
                    apiKey: nil,
                    model: "gpt-4o-mini"
                ),
            ]
        )

        let expected = ModelMetadata.supports(.tools, model: "gpt-4o-mini")

        #expect(client.supports(.tools, model: "fast") == expected)
        #expect(client.supports(.tools, model: "missing") == false)
    }

    @Test func unknownModelReturnsNil() {
        #expect(ModelMetadata.info(for: "definitely-not-a-real-model") == nil)
    }

    @Test func providerEndpointSupportLoads() {
        guard case let .object(root)? = ModelMetadata.providerEndpointSupport else {
            Issue.record("Expected provider endpoint support JSON object")
            return
        }
        #expect(root["providers"] != nil)
        #expect(root["endpoints"] != nil)
    }
}
