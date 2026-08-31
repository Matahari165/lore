import Foundation
import Testing
@testable import Lore

struct OpenAIResponsesClientTests {
    @Test func refusesRequestWithoutKey() async {
        let client = makeClient(key: nil) { _ in
            Issue.record("Aucune requête ne doit partir sans clé")
            throw URLError(.badServerResponse)
        }

        await #expect(throws: LoreAIError.missingAPIKey) {
            try await client.explain(sampleContext)
        }
    }

    @Test func sendsPrivateResponsesRequestWithExactModel() async throws {
        let client = makeClient(key: "secret-test-key") { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-test-key")
            let data = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["model"] as? String == "gpt-5.6-luna")
            #expect(json["store"] as? Bool == false)
            #expect((json["reasoning"] as? [String: Any])?["effort"] as? String == "low")
            let input = try #require(json["input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["developer", "user"])
            return Self.response(status: 200, body: #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Une explication simple."}]}]}"#)
        }

        #expect(try await client.explain(sampleContext) == "Une explication simple.")
    }

    @Test func parsesTopLevelOutputTextFallback() async throws {
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"output_text":"Résumé de la veille."}"#)
        }

        let result = try await client.recap(.init(title: "Livre", excerpt: "Contenu lu hier"))
        #expect(result == "Résumé de la veille.")
    }

    @Test func exposesAPIErrorsWithoutLeakingRequestContent() async {
        let client = makeClient(key: "key") { _ in
            Self.response(status: 429, body: #"{"error":{"message":"Quota dépassé"}}"#)
        }

        await #expect(throws: LoreAIError.requestFailed(statusCode: 429, message: "Quota dépassé")) {
            try await client.explain(sampleContext)
        }
    }

    @Test func rejectsMalformedSuccessfulResponse() async {
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"output":[]}"#)
        }

        await #expect(throws: LoreAIError.invalidResponse) {
            try await client.explain(sampleContext)
        }
    }

    private var sampleContext: BookAIContext {
        .init(
            title: "Livre",
            author: "Autrice",
            chapterTitle: "Chapitre 1",
            textBefore: "Contexte avant",
            selectedText: "Passage sélectionné",
            textAfter: "Contexte après"
        )
    }

    private func makeClient(
        key: String?,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OpenAIResponsesClient {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OpenAIResponsesClient(
            keyStore: StubKeyStore(key: key),
            session: session,
            configuration: .init(endpoint: URL(string: "https://example.test/v1/responses")!)
        )
    }

    private static func response(status: Int, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://example.test/v1/responses")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

private struct StubKeyStore: OpenAIAPIKeyStore {
    let key: String?
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String?) throws {}
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
