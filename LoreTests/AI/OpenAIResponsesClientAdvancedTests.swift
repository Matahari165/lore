import Foundation
import Testing
@testable import Lore

struct OpenAIResponsesClientAdvancedTests {
    @Test func advancedRequestsUseTheSamePrivateModelContract() async throws {
        AdvancedMockURLProtocol.handler = { request in
            let body = try Self.requestBody(of: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "gpt-5.6-luna")
            #expect(json["store"] as? Bool == false)
            #expect((json["input"] as? [[String: Any]])?.map { $0["role"] as? String } == ["developer", "user"])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"output_text":"Réponse bornée au contexte."}"#.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdvancedMockURLProtocol.self]
        let client = OpenAIResponsesClient(
            keyStore: AdvancedStubKeyStore(),
            session: URLSession(configuration: configuration),
            configuration: .init(endpoint: URL(string: "https://example.test/v1/responses")!)
        )

        #expect(try await client.summarizeChapter(.init(title: "Livre", chapterText: "Chapitre lu")) == "- Réponse bornée au contexte.")
        #expect(try await client.answerQuestion(.init(title: "Livre", readText: "Texte lu", question: "Que signifie ce passage ?")) == "- Réponse bornée au contexte.")
        #expect(try await client.discussEnding(.init(title: "Livre", readText: "Texte lu")) == "- Réponse bornée au contexte.")
    }

    private static func requestBody(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private struct AdvancedStubKeyStore: OpenAIAPIKeyStore {
    func loadAPIKey() throws -> String? { "test-key" }
    func saveAPIKey(_ key: String?) throws {}
}

private final class AdvancedMockURLProtocol: URLProtocol, @unchecked Sendable {
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
