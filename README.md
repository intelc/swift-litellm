# swift-litellm

[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](Package.swift)
[![CI](https://github.com/intelc/swift-litellm/actions/workflows/ci.yml/badge.svg)](https://github.com/intelc/swift-litellm/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Model routing for native Swift apps.** Configure aliases like `"smart"` and `"local"`, stream normalized events, and fall back across OpenAI-compatible endpoints, Anthropic, Gemini, and Ollama.

![swift-litellm architecture](Assets/readme/architecture.svg)

- **Aliases instead of provider lock-in:** app code calls `"smart"` or `"fast"`, not scattered provider model IDs.
- **Cloud-first, local-fallback:** route from Anthropic or Gemini to OpenAI-compatible endpoints or local Ollama.
- **LiteLLM-inspired, not a gateway:** no server target, no proxy process, no provider SDK dependencies.

```swift
let response = try await llm.chat(
    model: "smart",
    messages: [.user("Summarize this.")]
)
```

## When To Use This

| You want | Use `swift-litellm`? |
| --- | --- |
| A small router layer inside an iOS/macOS app | Yes |
| User-selectable cloud/local providers | Yes |
| OpenAI-compatible endpoint portability | Yes |
| LiteLLM-style aliases, retries, fallbacks, and metadata | Yes |
| A server gateway, admin UI, budgets, or virtual keys | Use LiteLLM/Bifrost/Portkey instead |
| A broad AI app framework with middleware and agents | Consider Swift AI SDK or Conduit |

## Why This Exists

The Python ecosystem has [LiteLLM](https://github.com/BerriAI/litellm): a Python SDK and AI gateway that exposes 100+ providers through an OpenAI-shaped interface with routing, fallbacks, spend tracking, guardrails, and proxy features.

The Swift ecosystem has strong multi-provider SDKs too:

- [Swift AI SDK](https://github.com/teunlao/swift-ai-sdk) is a broad Vercel AI SDK-style framework for Swift with many provider modules, streaming, tools, structured outputs, middleware, and MCP-oriented workflows.
- [Conduit](https://github.com/christopherkarani/Conduit) is a type-safe Swift framework for cloud and on-device language models, with a strong local/Apple Silicon story through MLX and actor-based providers.

`swift-litellm` aims at a smaller gap:

> A lightweight router layer for native apps that want LiteLLM-style aliases, retries, fallbacks, normalized streaming, provider transforms, and LiteLLM-derived model metadata without running a gateway.

It is not trying to be a full agent framework, a gateway, or a replacement for provider-rich SDKs. It is the small piece you put between app code and model providers when you want model portability to stay boring.

## How It Compares

| Project | Best For | Shape |
| --- | --- | --- |
| [LiteLLM](https://github.com/BerriAI/litellm) | Python apps, AI gateways, provider breadth, proxy features | Python SDK + server gateway |
| [Swift AI SDK](https://github.com/teunlao/swift-ai-sdk) | Full Swift AI SDK surface with tools, structured outputs, middleware, and many modules | Broad provider framework |
| [Conduit](https://github.com/christopherkarani/Conduit) | Type-safe local/cloud inference, Apple Silicon, MLX/CoreML-oriented apps | Native Swift inference framework |
| `swift-litellm` | Lightweight model routing, aliases, fallbacks, normalized chat/streaming for native apps | Small Swift router SDK |

## Install

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/intelc/swift-litellm.git", branch: "main")
]
```

Then add the product to your app target:

```swift
.product(name: "LiteLLM", package: "swift-litellm")
```

## Quick Start

```swift
import Foundation
import LiteLLM

let llm = LiteLLMClient(
    models: [
        "fast": .openAICompatible(
            baseURL: URL(string: "https://openrouter.ai/api")!,
            apiKey: openRouterKey,
            model: "openai/gpt-4o-mini"
        ),
        "smart": .anthropic(
            apiKey: anthropicKey,
            model: "claude-sonnet-4-5"
        ),
        "gemini": .gemini(
            apiKey: geminiKey,
            model: "gemini-2.5-pro"
        ),
        "local": .ollama(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2"
        )
    ],
    fallbacks: [
        "smart": ["gemini", "fast", "local"]
    ]
)

let response = try await llm.chat(
    model: "smart",
    messages: [
        .system("Be concise."),
        .user("Summarize this.")
    ]
)

print(response.message.content ?? "")
```

## Routing And Fallbacks

The main abstraction is a model alias. Your UI and features can ask for `"smart"`, while the client decides what concrete provider/model that means.

```swift
let llm = LiteLLMClient(
    models: [
        "smart": .anthropic(apiKey: anthropicKey, model: "claude-sonnet-4-5"),
        "gemini": .gemini(apiKey: geminiKey, model: "gemini-2.5-pro"),
        "fast": .openAICompatible(baseURL: openRouterURL, apiKey: openRouterKey, model: "openai/gpt-4o-mini"),
        "local": .ollama(baseURL: ollamaURL, model: "llama3.2")
    ],
    fallbacks: [
        "smart": ["gemini", "fast", "local"]
    ]
)
```

```text
"smart" → Anthropic → Gemini → OpenAI-compatible → Ollama
```

That is the LiteLLM-inspired part: app code depends on a capability alias, not a single vendor endpoint.

## Streaming

```swift
let stream = try llm.streamChat(
    model: "fast",
    messages: [.user("Draft a short reply.")]
)

for try await event in stream {
    switch event {
    case let .textDelta(text):
        print(text, terminator: "")
    case let .toolCallDelta(toolCall):
        print("tool:", toolCall.name, toolCall.arguments)
    case let .messageCompleted(response):
        print("done:", response.finishReason ?? "unknown")
    case .done:
        break
    }
}
```

## Tool Calls

```swift
let weather = ToolDefinition(
    name: "get_weather",
    description: "Get the current weather for a city.",
    parameters: [
        "type": "object",
        "properties": [
            "city": [
                "type": "string"
            ]
        ],
        "required": ["city"]
    ]
)

let response = try await llm.chat(
    model: "smart",
    messages: [.user("Should I bring a jacket in San Francisco?")],
    tools: [weather]
)

if let call = response.message.toolCalls?.first {
    print(call.name, call.arguments)
}
```

## What You Get

- **Model aliases:** call `"smart"`, `"fast"`, or `"local"` from app code instead of hardcoding provider model IDs everywhere.
- **Fallback chains:** fail from Anthropic to Gemini to OpenAI-compatible to local Ollama.
- **OpenAI-compatible first:** works with OpenRouter, LiteLLM proxy, vLLM, LM Studio, and other OpenAI-shaped endpoints.
- **Native-app friendly:** Swift 6, async/await, `URLSession`, no server framework dependency.
- **Normalized outputs:** one `ChatResponse`, one `StreamEvent`, one `ToolCall` shape.
- **LiteLLM metadata:** bundled model pricing/context/provider metadata generated from LiteLLM resources.
- **Testable transforms:** provider adapters are pure enough to fixture-test request and response parity.

## Provider Matrix

| Provider | Chat | Streaming | Tools | JSON mode intent | Usage | Status |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI-compatible | Yes | Yes | Yes | Yes | Yes | Early |
| Anthropic | Yes | Yes | Yes | Basic | Yes | Early |
| Gemini | Yes | Yes | Yes | Basic | Yes | Early |
| Ollama | Yes | Yes | Basic | Basic | Basic | Early |

OpenAI-compatible endpoints include services such as OpenRouter, LiteLLM proxy, vLLM, LM Studio, and any endpoint that implements `/v1/chat/completions`.

## Current Scope

Supported in this early V1:

- Chat completions
- Streaming chat
- Basic tool definition and tool-call normalization
- Basic structured-output / JSON-mode intent
- Usage normalization
- Retries and fallbacks
- LiteLLM-derived model metadata
- Providers: OpenAI-compatible, Anthropic, Gemini, Ollama

Out of scope for now:

- Gateway/server target
- Admin UI, virtual keys, budgets, spend tracking, caching, guardrails
- Embeddings, images, audio, batches, rerank
- OpenAI Responses API
- Full agent loop or MCP client

## Model Metadata

`swift-litellm` ships generated metadata from LiteLLM:

- `model_prices_and_context_window.json`
- `provider_endpoints_support.json`
- `litellm-upstream.json`

Use it directly:

```swift
if let info = ModelMetadata.info(for: "gpt-4o-mini") {
    print(info.litellmProvider ?? "unknown")
    print(info.maxInputTokens ?? 0)
    print(info.supportsFunctionCalling ?? false)
}
```

Refresh the metadata from a local LiteLLM checkout:

```bash
python3 Scripts/sync_litellm_metadata.py --litellm-dir /path/to/litellm
```

Validate the checked-in resources:

```bash
python3 Scripts/sync_litellm_metadata.py --check
```

## Roadmap

The next work is tracked in [TODO.md](TODO.md). The immediate priority is deeper provider parity:

- richer tool-call fixtures
- streaming tool-call deltas
- provider error-body normalization
- structured output quirks
- opt-in live tests
- streaming accumulation helpers
- model capability helpers
- better key-provider ergonomics for apps

## Safety

This repo includes a local pre-commit hook at `.githooks/pre-commit` that blocks common API keys, private keys, and accidental `.env` commits.

Enable it after cloning:

```bash
git config core.hooksPath .githooks
```

## Development

```bash
swift test
python3 Scripts/sync_litellm_metadata.py --check
```

The test suite covers provider request transforms, response parsing, streaming event parsing, router retry/fallback/cancellation behavior, and metadata loading.

## License

MIT. LiteLLM-derived metadata is generated from the upstream LiteLLM project; see `Sources/LiteLLM/Resources/metadata/litellm-upstream.json` for the pinned source commit.
