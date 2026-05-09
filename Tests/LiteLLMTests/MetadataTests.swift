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
