import Foundation

public enum LiteLLMError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownModelAlias(String)
    case invalidRequest(String)
    case transport(statusCode: Int, body: String)
    case provider(String)
    case decoding(String)
    case cancelled

    public var description: String {
        switch self {
        case let .unknownModelAlias(alias):
            "Unknown model alias: \(alias)"
        case let .invalidRequest(message):
            "Invalid request: \(message)"
        case let .transport(statusCode, body):
            "Provider returned HTTP \(statusCode): \(body)"
        case let .provider(message):
            "Provider error: \(message)"
        case let .decoding(message):
            "Decoding error: \(message)"
        case .cancelled:
            "Request cancelled"
        }
    }

    var isRetryable: Bool {
        switch self {
        case let .transport(statusCode, _):
            [408, 409, 429, 500, 502, 503, 504].contains(statusCode)
        case .provider:
            true
        case .cancelled, .decoding, .invalidRequest, .unknownModelAlias:
            false
        }
    }
}

extension Error {
    var asLiteLLMError: LiteLLMError {
        if let error = self as? LiteLLMError {
            return error
        }
        if self is CancellationError {
            return .cancelled
        }
        return .provider(String(describing: self))
    }
}
