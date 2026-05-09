import Foundation

public struct ModelInfo: Codable, Equatable, Sendable {
    public var litellmProvider: String?
    public var mode: String?
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?
    public var maxTokens: Int?
    public var inputCostPerToken: Double?
    public var outputCostPerToken: Double?
    public var supportsFunctionCalling: Bool?
    public var supportsParallelFunctionCalling: Bool?
    public var supportsPromptCaching: Bool?
    public var supportsResponseSchema: Bool?
    public var supportsToolChoice: Bool?
    public var supportsVision: Bool?

    enum CodingKeys: String, CodingKey {
        case litellmProvider
        case mode
        case maxInputTokens
        case maxOutputTokens
        case maxTokens
        case inputCostPerToken
        case outputCostPerToken
        case supportsFunctionCalling
        case supportsParallelFunctionCalling
        case supportsPromptCaching
        case supportsResponseSchema
        case supportsToolChoice
        case supportsVision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        litellmProvider = try container.decodeIfPresent(String.self, forKey: .litellmProvider)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        maxInputTokens = container.lossyInt(forKey: .maxInputTokens)
        maxOutputTokens = container.lossyInt(forKey: .maxOutputTokens)
        maxTokens = container.lossyInt(forKey: .maxTokens)
        inputCostPerToken = container.lossyDouble(forKey: .inputCostPerToken)
        outputCostPerToken = container.lossyDouble(forKey: .outputCostPerToken)
        supportsFunctionCalling = container.lossyBool(forKey: .supportsFunctionCalling)
        supportsParallelFunctionCalling = container.lossyBool(forKey: .supportsParallelFunctionCalling)
        supportsPromptCaching = container.lossyBool(forKey: .supportsPromptCaching)
        supportsResponseSchema = container.lossyBool(forKey: .supportsResponseSchema)
        supportsToolChoice = container.lossyBool(forKey: .supportsToolChoice)
        supportsVision = container.lossyBool(forKey: .supportsVision)
    }
}

extension KeyedDecodingContainer {
    func lossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func lossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func lossyBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Bool(value) }
        return nil
    }
}

public struct LiteLLMUpstreamMetadata: Codable, Equatable, Sendable {
    public var source: String?
    public var commit: String?
    public var ref: String?
}

public enum ModelMetadata {
    public static func info(for model: String) -> ModelInfo? {
        modelCostMap[model]
    }

    public static var upstream: LiteLLMUpstreamMetadata? {
        load("litellm-upstream", as: LiteLLMUpstreamMetadata.self)
    }

    public static var modelCostMap: [String: ModelInfo] {
        load("model_prices_and_context_window", as: [String: ModelInfo].self) ?? [:]
    }

    public static var providerEndpointSupport: JSONValue? {
        load("provider_endpoints_support", as: JSONValue.self)
    }

    private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "metadata")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let url else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}
