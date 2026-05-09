import Foundation
import LiteLLM

public extension Provider {
    static func localOpenAICompatible(
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        providerName: String = "local-openai-compatible"
    ) -> Provider {
        .openAICompatible(baseURL: baseURL, apiKey: apiKey, model: model, providerName: providerName)
    }

    static func lmStudio(baseURL: URL = URL(string: "http://localhost:1234")!, apiKey: String? = nil, model: String) -> Provider {
        .localOpenAICompatible(baseURL: baseURL, apiKey: apiKey, model: model, providerName: "lm-studio")
    }

    static func llamaCppServer(baseURL: URL = URL(string: "http://localhost:8080")!, apiKey: String? = nil, model: String) -> Provider {
        .localOpenAICompatible(baseURL: baseURL, apiKey: apiKey, model: model, providerName: "llama.cpp")
    }

    static func mlxServer(baseURL: URL = URL(string: "http://localhost:8080")!, apiKey: String? = nil, model: String) -> Provider {
        .localOpenAICompatible(baseURL: baseURL, apiKey: apiKey, model: model, providerName: "mlx-server")
    }
}
