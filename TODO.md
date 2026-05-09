# TODO

## Next High-Value Work

- Keep tightening provider adapters as those fixtures land, without special cases leaking into app code.
- Consider splitting built-in provider implementations into optional SwiftPM products such as `LiteLLMOpenAICompatible`, `LiteLLMAnthropic`, `LiteLLMGemini`, and `LiteLLMOllama`, with `LiteLLM` remaining the convenience product.
- Explore true in-process local providers in `LiteLLMLocalInference` using MLX/CoreML/Foundation Models behind the same normalized chat/streaming surface.
- Use Conduit as the mature local-inference reference point when deciding how far `LiteLLMLocalInference` should go, especially around MLX/CoreML provider boundaries, model lifecycle, and Apple Silicon ergonomics.
- Keep model download, cache management, warmup, memory presets, and tokenizer-specific behavior out of core unless real usage demands it.

## Done

- Added provider parity fixtures/tests for Anthropic tool calls, Anthropic streaming tool-call deltas, Gemini tool calls, OpenAI-compatible streaming tool-call chunks, and Gemini structured-output JSON schema intent.
- Tightened adapters for partial OpenAI-compatible streaming tool-call chunks, Gemini tool responses, and Gemini JSON schema request mapping.
- Added opt-in live provider smoke tests gated by `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, and `OLLAMA_BASE_URL`.
- Added `ChatStreamAccumulator` plus `collectChatResponse(from:model:provider:)`.
- Added model capability helpers with `ModelMetadata.supports(_:model:)`, `ModelInfo.supports(_:)`, and `llm.supports(_:model:)`.
- Added provider error-body normalization for common OpenAI-compatible, Anthropic, Gemini, Ollama, and plain-text error payloads.
- Added Ollama tool-call request fixtures plus response and streaming coverage for object-style tool arguments.
- Added Gemini streaming parser coverage for SSE payloads, JSON-array streams, ignored bracket lines, and trailing-comma chunks.
- Added deeper usage normalization for partial OpenAI-compatible and Gemini token payloads.
- Added key-provider closures, per-call credential overrides through `providerOptions["api_key"]`, and a README Keychain lookup example.
- Added README examples for cloud-to-local fallback, tool-call loops, structured output, and BYO OpenAI-compatible endpoints.
- Reworked `Provider` into a public adapter-backed route target so third-party providers can plug into aliases, retries, fallbacks, normalized chat, and streaming without editing core.
- Added `ChatProvider` as the public execution seam so in-process/non-HTTP providers can bypass HTTP adapters while still using aliases, retries, and fallbacks.
- Added `LiteLLMLocalInference` with local OpenAI-compatible presets for LM Studio, llama.cpp server, MLX server, and generic local endpoints.
- Added closure-backed `mlxInProcess` and generic `inProcess` providers for app-owned local runtimes.
- Added conditional Apple Foundation Models provider support behind `canImport(FoundationModels)`.
- Audited Conduit's local provider design and adopted two relevant patterns: explicit local-runtime cancellation hooks and a Foundation Models stub that keeps code buildable when Apple's framework is unavailable.

## Later

- Consider embeddings only after chat/tool/streaming behavior feels boringly reliable.
- Consider a tiny demo app target, but keep the package SDK-only.
- Consider a gateway executable only if real users ask for server-side Swift.
