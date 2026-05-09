import Foundation
import Testing
@testable import LiteLLM

func decodedFixture(_ name: String) throws -> JSONValue {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
    )
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}

func bodyJSON(_ request: ProviderHTTPRequest) throws -> JSONValue {
    let data = try JSONCoding.data(request.body)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

actor MockHTTPTransport: HTTPTransport {
    private var responses: [(Int, Data)]
    private var storedRequests: [HTTPRequest] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    var requests: [HTTPRequest] {
        storedRequests
    }

    func data(for request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        storedRequests.append(request)
        let response = responses.isEmpty ? (500, Data()) : responses.removeFirst()
        let http = HTTPURLResponse(url: request.url, statusCode: response.0, httpVersion: nil, headerFields: nil)!
        return (response.1, http)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        throw LiteLLMError.provider("MockHTTPTransport does not implement streaming bytes")
    }
}

struct SlowHTTPTransport: HTTPTransport {
    func data(for request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .seconds(5))
        let http = HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("{}".utf8), http)
    }

    func bytes(for request: HTTPRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        throw LiteLLMError.provider("SlowHTTPTransport does not implement streaming bytes")
    }
}
