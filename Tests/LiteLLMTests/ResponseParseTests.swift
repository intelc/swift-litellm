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

    @Test func partialUsageCountsAreCompletedFromTotals() throws {
        let openAI = OpenAICompatibleAdapter(baseURL: URL(string: "https://example.com")!, apiKey: nil, model: "gpt")
        let openAIData = Data("""
        {
          "id": "chatcmpl_1",
          "model": "gpt",
          "choices": [{
            "message": {"role": "assistant", "content": "Hi"},
            "finish_reason": "stop"
          }],
          "usage": {"prompt_tokens": 5, "total_tokens": 12}
        }
        """.utf8)
        let gemini = GeminiAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "gemini")
        let geminiData = Data("""
        {
          "candidates": [{
            "content": {"parts": [{"text": "Hi"}]},
            "finish_reason": "STOP"
          }],
          "usage_metadata": {
            "prompt_token_count": 3,
            "total_token_count": 9
          }
        }
        """.utf8)

        #expect(try openAI.parseResponse(data: openAIData).usage == Usage(promptTokens: 5, completionTokens: 7, totalTokens: 12))
        #expect(try gemini.parseResponse(data: geminiData).usage == Usage(promptTokens: 3, completionTokens: 6, totalTokens: 9))
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

    @Test func openAIStreamingToolCallChunksCanBePartial() throws {
        let adapter = OpenAICompatibleAdapter(baseURL: URL(string: "https://example.com")!, apiKey: nil, model: "gpt")

        let start = try adapter.parseStreamLine("""
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"q\\""}}]},"finish_reason":null}]}
        """)
        let arguments = try adapter.parseStreamLine("""
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"x\\"}"}}]},"finish_reason":null}]}
        """)
        let empty = try adapter.parseStreamLine("""
        data: {"choices":[{"delta":{"tool_calls":[{"index":0}]},"finish_reason":null}]}
        """)

        #expect(start == [.toolCallDelta(ToolCall(id: "call_1", name: "lookup", arguments: "{\"q\""))])
        #expect(arguments == [.toolCallDelta(ToolCall(name: "", arguments: ":\"x\"}"))])
        #expect(empty == [.toolCallDelta(ToolCall(name: "", arguments: ""))])
    }

    @Test func anthropicStreamingToolCallDeltasAreNormalized() throws {
        let adapter = AnthropicAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "claude")

        let start = try adapter.parseStreamLine("""
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup","input":{}}}
        """)
        let delta = try adapter.parseStreamLine("""
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"q\\":\\"x\\"}"}}
        """)

        #expect(start == [.toolCallDelta(ToolCall(id: "toolu_1", name: "lookup", arguments: "{}"))])
        #expect(delta == [.toolCallDelta(ToolCall(id: nil, name: "", arguments: "{\"q\":\"x\"}"))])
    }

    @Test func geminiResponseAndStreamingNormalizeToolCalls() throws {
        let adapter = GeminiAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "gemini")
        let data = Data("""
        {
          "candidates": [{
            "content": {
              "parts": [{
                "function_call": {
                  "name": "lookup",
                  "args": {"q": "x"}
                }
              }]
            },
            "finish_reason": "STOP"
          }],
          "usage_metadata": {
            "prompt_token_count": 3,
            "candidates_token_count": 4,
            "total_token_count": 7
          }
        }
        """.utf8)

        let response = try adapter.parseResponse(data: data)
        let events = try adapter.parseStreamLine("data: \(String(decoding: data, as: UTF8.self))")

        #expect(response.message.toolCalls == [ToolCall(name: "lookup", arguments: "{\"q\":\"x\"}")])
        #expect(response.usage == Usage(promptTokens: 3, completionTokens: 4, totalTokens: 7))
        #expect(events == [.toolCallDelta(ToolCall(name: "lookup", arguments: "{\"q\":\"x\"}")), .done])
    }

    @Test func geminiStreamingParserHandlesJsonArrayAndTrailingCommaLines() throws {
        let adapter = GeminiAdapter(baseURL: URL(string: "https://example.com")!, apiKey: "key", model: "gemini")

        let arrayEvents = try adapter.parseStreamLine("""
        [{"candidates":[{"content":{"parts":[{"text":"hel"}]},"finish_reason":null}]},{"candidates":[{"content":{"parts":[{"text":"lo"}]},"finish_reason":"STOP"}]}]
        """)
        let commaEvents = try adapter.parseStreamLine("""
        {"candidates":[{"content":{"parts":[{"text":"!"}]},"finish_reason":null}]},
        """)
        let bracketEvents = try adapter.parseStreamLine("[")

        #expect(arrayEvents == [.textDelta("hel"), .textDelta("lo"), .done])
        #expect(commaEvents == [.textDelta("!")])
        #expect(bracketEvents == [])
    }

    @Test func ollamaResponseAndStreamingNormalizeToolCallsWithObjectArguments() throws {
        let adapter = OllamaAdapter(baseURL: URL(string: "http://localhost:11434")!, model: "llama")
        let data = Data("""
        {
          "model": "llama",
          "message": {
            "role": "assistant",
            "content": "",
            "tool_calls": [{
              "function": {
                "name": "lookup",
                "arguments": {"q": "x"}
              }
            }]
          },
          "done": true,
          "prompt_eval_count": 6,
          "eval_count": 2
        }
        """.utf8)
        let streamLine = """
        {
          "model": "llama",
          "message": {
            "role": "assistant",
            "content": "",
            "tool_calls": [{
              "function": {
                "name": "lookup",
                "arguments": {"q": "x"}
              }
            }]
          },
          "done": false
        }
        """

        let response = try adapter.parseResponse(data: data)
        let events = try adapter.parseStreamLine(streamLine)

        #expect(response.message.content == nil)
        #expect(response.message.toolCalls == [ToolCall(name: "lookup", arguments: "{\"q\":\"x\"}")])
        #expect(response.usage == Usage(promptTokens: 6, completionTokens: 2))
        #expect(events == [.toolCallDelta(ToolCall(name: "lookup", arguments: "{\"q\":\"x\"}"))])
    }

    @Test func streamAccumulatorCollectsFinalResponse() async throws {
        let stream = AsyncStream<StreamEvent> { continuation in
            continuation.yield(.textDelta("Use "))
            continuation.yield(.textDelta("tools"))
            continuation.yield(.toolCallDelta(ToolCall(id: "call_1", name: "lookup", arguments: "{\"q\"")))
            continuation.yield(.toolCallDelta(ToolCall(name: "", arguments: ":\"x\"}")))
            continuation.yield(.done)
            continuation.finish()
        }

        let response = try await collectChatResponse(from: stream, model: "gpt", provider: "openai-compatible")

        #expect(response.model == "gpt")
        #expect(response.provider == "openai-compatible")
        #expect(response.message.content == .text("Use tools"))
        #expect(response.message.toolCalls == [ToolCall(id: "call_1", name: "lookup", arguments: "{\"q\":\"x\"}")])
    }
}
