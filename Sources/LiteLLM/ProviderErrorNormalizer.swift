import Foundation

func normalizedProviderErrorBody(_ data: Data, provider: String) -> String {
    let raw = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !raw.isEmpty else { return "" }
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
        return raw
    }
    return normalizedProviderErrorBody(json, provider: provider) ?? raw
}

private func normalizedProviderErrorBody(_ value: JSONValue, provider: String) -> String? {
    guard case let .object(root) = value else { return nil }

    if let error = root["error"] {
        switch error {
        case let .string(message):
            return formatProviderError(provider: provider, message: message)
        case let .object(object):
            return formatProviderError(
                provider: provider,
                message: stringValue(object["message"]) ?? stringValue(object["detail"]),
                type: stringValue(object["type"]),
                code: stringValue(object["code"]),
                status: stringValue(object["status"])
            )
        default:
            break
        }
    }

    return formatProviderError(
        provider: provider,
        message: stringValue(root["message"]) ?? stringValue(root["detail"]),
        type: stringValue(root["type"]),
        code: stringValue(root["code"]),
        status: stringValue(root["status"])
    )
}

private func formatProviderError(
    provider: String,
    message: String?,
    type: String? = nil,
    code: String? = nil,
    status: String? = nil
) -> String? {
    guard let message, !message.isEmpty else { return nil }
    let metadata = [type, status, code]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    let prefix = ([provider] + metadata).joined(separator: " ")
    return "\(prefix): \(message)"
}

private func stringValue(_ value: JSONValue?) -> String? {
    switch value {
    case let .string(value):
        value
    case let .number(value):
        value.rounded() == value ? String(Int(value)) : String(value)
    case let .bool(value):
        String(value)
    case .object, .array, .null, .none:
        nil
    }
}
