import Foundation
import Testing
@testable import LiteLLM

@Suite("Response parsing")
struct ResponseParseTests {
    @Test func openAIResponseNormalizesTextToolCallsAndUsage() throws {
        let adapter = OpenAICompatibleAdapter(baseURL: URL(string: "https://example.com")!, apiKey: nil, model: "gpt")
        let data = Data("""
        {
          "id": "chatcmpl_1",
          "model": "gpt",
          "choices": [{
            "message": {
              "role": "assistant",
              "content": "Hi",
              "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": {"name": "lookup", "arguments": "{\\"q\\":\\"x\\"}"}
              }]
            },
            "finish_reason": "tool_calls"
          }],
          "usage": {"prompt_tokens": 5, "completion_tokens": 7, "total_tokens": 12}
        }
        """.utf8)

        let response = try adapter.parseResponse(data: data)

        #expect(response.id == "chatcmpl_1")
        #expect(response.message.content == .text("Hi"))
        #expect(response.message.toolCalls == [ToolCall(id: "call_1", name: "lookup", arguments: "{\"q\":\"x\"}")])
        #expect(response.usage == Usage(promptTokens: 5, completionTokens: 7, totalTokens: 12))
    }

    @Test func anthropicResponseNormalizesContentBlocksAndUsage() throws {
        let adapter = AnthropicAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "claude")
        let data = Data("""
        {
          "id": "msg_1",
          "model": "claude",
          "content": [
            {"type": "text", "text": "Use "},
            {"type": "text", "text": "tools"},
            {"type": "tool_use", "id": "toolu_1", "name": "lookup", "input": {"q": "x"}}
          ],
          "stop_reason": "tool_use",
          "usage": {
            "input_tokens": 10,
            "cache_creation_input_tokens": 2,
            "cache_read_input_tokens": 3,
            "output_tokens": 4
          }
        }
        """.utf8)

        let response = try adapter.parseResponse(data: data)

        #expect(response.message.content == .text("Use tools"))
        #expect(response.message.toolCalls?.first?.id == "toolu_1")
        #expect(response.message.toolCalls?.first?.name == "lookup")
        #expect(response.usage == Usage(promptTokens: 15, completionTokens: 4))
    }

    @Test func streamingParsersEmitNormalizedEvents() throws {
        let openAI = OpenAICompatibleAdapter(baseURL: URL(string: "https://example.com")!, apiKey: nil, model: "gpt")
        let openAIEvents = try openAI.parseStreamLine("""
        data: {"choices":[{"delta":{"content":"hel"},"finish_reason":null}]}
        """)
        #expect(openAIEvents == [.textDelta("hel")])

        let anthropic = AnthropicAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "claude")
        let anthropicEvents = try anthropic.parseStreamLine("""
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}}
        """)
        #expect(anthropicEvents == [.textDelta("lo")])

        let ollama = OllamaAdapter(baseURL: URL(string: "http://localhost:11434")!, model: "llama")
        let ollamaEvents = try ollama.parseStreamLine("""
        {"message":{"role":"assistant","content":"!"},"done":false}
        """)
        #expect(ollamaEvents == [.textDelta("!")])
    }
}
