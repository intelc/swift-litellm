# TODO

## Next High-Value Work

- Expand provider parity fixtures for the real failure-prone paths: Anthropic tool calls, Anthropic streaming tool-call deltas, Gemini tool calls, Gemini streaming quirks, Ollama tool calls, OpenAI-compatible streaming tool-call chunks, structured output / JSON mode, provider error bodies, and usage normalization.
- Tighten provider adapters until those fixtures pass without special cases leaking into app code.
- Add opt-in live provider tests gated by environment variables: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, and `OLLAMA_BASE_URL`.
- Add a streaming accumulation helper so apps can either consume `AsyncSequence<StreamEvent>` directly or collect a final `ChatResponse`.
- Add a model capability API over LiteLLM metadata, for example `ModelMetadata.info(for:)` plus client helpers such as `llm.supports(.tools, model:)`.
- Improve key ergonomics for native apps: key-provider closures, per-call credential overrides, and a Keychain-backed example.
- Add more README examples once the richer fixtures land: fallback from cloud to local, tool-call loop, structured output, and BYO OpenAI-compatible endpoint.

## Later

- Consider embeddings only after chat/tool/streaming behavior feels boringly reliable.
- Consider a tiny demo app target, but keep the package SDK-only.
- Consider a gateway executable only if real users ask for server-side Swift.
