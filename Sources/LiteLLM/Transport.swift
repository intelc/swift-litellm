import Foundation

struct HTTPRequest: Sendable {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data
}

protocol HTTPTransport: Sendable {
    func data(for request: HTTPRequest) async throws -> (Data, HTTPURLResponse)
    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse)
}

struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request.urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiteLLMError.provider("Expected HTTPURLResponse")
        }
        return (data, httpResponse)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request.urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiteLLMError.provider("Expected HTTPURLResponse")
        }
        return (bytes, httpResponse)
    }
}

extension HTTPRequest {
    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func data(_ object: [String: JSONValue]) throws -> Data {
        try encoder.encode(object)
    }
}
