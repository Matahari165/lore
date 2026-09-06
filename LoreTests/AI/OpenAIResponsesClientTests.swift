import Foundation
import ReadiumShared
import Testing
@testable import Lore

@Suite(.serialized)
struct OpenAIResponsesClientTests {
    @Test func formatterAlwaysProducesSeparatedMarkdownBullets() {
        let formatted = LoreAIResponseFormatter.bulleted("Première phrase. Deuxième phrase.")

        #expect(formatted == "- Première phrase.\n\n- Idée essentielle : Deuxième phrase.")
    }

    @Test func formatterNormalizesExistingMarkers() {
        let formatted = LoreAIResponseFormatter.bulleted("• Simple\n2. Clair\n- Court")

        #expect(formatted == "- Simple\n\n- Clair\n\n- Idée essentielle : Court")
    }

    @Test func formatterLimitsCountAndSentenceLength() {
        let long = (1...8).map { index in
            "\(index). " + Array(repeating: "mot", count: 30).joined(separator: " ")
        }.joined(separator: "\n")

        let bullets = LoreAIResponseFormatter.bulleted(long).components(separatedBy: "\n\n")
        #expect(bullets.count == 6)
        #expect(bullets.allSatisfy { $0.split(whereSeparator: \Character.isWhitespace).count <= 26 })
    }

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
            let data = try Self.requestBody(of: request)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["model"] as? String == "gpt-5.6-luna")
            #expect(json["store"] as? Bool == false)
            #expect(json["max_output_tokens"] as? Int == 800)
            #expect((json["reasoning"] as? [String: Any])?["effort"] as? String == "low")
            let input = try #require(json["input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["developer", "user"])
            return Self.response(status: 200, body: #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Une explication simple."}]}]}"#)
        }

        #expect(try await client.explain(sampleContext) == "- Idée essentielle : Une explication simple.")
    }

    @Test func parsesTopLevelOutputTextFallback() async throws {
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"output_text":"Résumé de la veille."}"#)
        }

        let result = try await client.recap(.init(title: "Livre", excerpt: "Contenu lu hier"))
        #expect(result == "- Idée essentielle : Résumé de la veille.")
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

    @Test func chatUsesStrictSchemaAndAcceptsOnlyKnownSourceID() async throws {
        let bookID = UUID()
        let source = try chatSource(bookID: bookID, id: "local-opaque-id", progression: 0.4)
        let client = makeClient(key: "key") { request in
            let body = try Self.requestBody(of: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["store"] as? Bool == false)
            let format = try #require(((json["text"] as? [String: Any])?["format"] as? [String: Any]))
            let expectedFormat: [String: Any] = [
                "type": "json_schema",
                "name": "lore_chat_answer",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "answer": ["type": "string"],
                        "source_ids": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["answer", "source_ids"],
                    "additionalProperties": false
                ]
            ]
            #expect(NSDictionary(dictionary: format).isEqual(to: expectedFormat))
            let schema = try #require(format["schema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            let answer = try #require(properties["answer"] as? [String: Any])
            let sourceIDs = try #require(properties["source_ids"] as? [String: Any])
            #expect(answer["items"] == nil)
            #expect((sourceIDs["items"] as? [String: Any])?["type"] as? String == "string")
            let input = try #require(json["input"] as? [[String: Any]])
            #expect((input.last?["content"] as? String)?.contains("\"source_id\":\"local-opaque-id\"") == true)
            return Self.response(status: 200, body: #"{"status":"completed","output_text":"{\"answer\":\"Réponse.\",\"source_ids\":[\"local-opaque-id\",\"unknown\"]}"}"#)
        }
        let response = try await client.chat(.init(
            bookID: bookID,
            title: "Livre",
            stage: .inProgress,
            readFrontierProgression: 0.5,
            excerpts: [.init(text: "Texte", progression: 0.4, source: source)],
            question: "Pourquoi ?"
        ))
        #expect(response.text == "- Idée essentielle : Réponse.")
        #expect(response.sources == [source])
    }

    @Test func unknownSourceIDProducesNoClickableSource() async throws {
        let bookID = UUID()
        let source = try chatSource(bookID: bookID, id: "known", progression: 0.4)
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"status":"completed","output_text":"{\"answer\":\"Réponse.\",\"source_ids\":[\"unknown\"]}"}"#)
        }
        let response = try await client.chat(validContext(bookID: bookID, sources: [source]))
        #expect(response.sources.isEmpty)
    }

    @Test func duplicateModelCitationIDsAreNormalizedToOneSource() async throws {
        let bookID = UUID()
        let source = try chatSource(bookID: bookID, id: "known", progression: 0.4)
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"status":"completed","output_text":"{\"answer\":\"Réponse.\",\"source_ids\":[\"known\",\"known\"]}"}"#)
        }
        let response = try await client.chat(validContext(bookID: bookID, sources: [source]))
        #expect(response.sources == [source])
    }

    @Test func clippedExcerptReturnsAnEquallyClippedLocator() async throws {
        let bookID = UUID()
        let text = String(repeating: "a", count: 12_010)
        let source = try chatSource(bookID: bookID, id: "known", progression: 0.4, text: text)
        let client = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"status":"completed","output_text":"{\"answer\":\"Réponse.\",\"source_ids\":[\"known\"]}"}"#)
        }
        let response = try await client.chat(validContext(bookID: bookID, sources: [source], text: text))
        let returned = try #require(response.sources.first)
        let locator = try Locator(jsonData: returned.locatorJSON)
        #expect(locator.text.highlight?.count == 12_000)
    }

    @Test func duplicateSourceIDsAreRejectedBeforeRequest() async throws {
        let bookID = UUID()
        let accepted = try chatSource(bookID: bookID, id: "duplicate", progression: 0.4)
        let duplicate = try chatSource(bookID: bookID, id: "duplicate", progression: 0.3)
        let client = rejectingRequestClient()
        await #expect(throws: LoreAIError.invalidChatContext) {
            try await client.chat(validContext(bookID: bookID, sources: [accepted, duplicate]))
        }
    }

    @Test func foreignBookSourceIsRejectedBeforeRequest() async throws {
        let bookID = UUID()
        let foreign = try chatSource(bookID: UUID(), id: "foreign", progression: 0.2)
        await #expect(throws: LoreAIError.invalidChatContext) {
            try await rejectingRequestClient().chat(validContext(bookID: bookID, sources: [foreign]))
        }
    }

    @Test func unprovenNilProgressionSourceIsRejectedBeforeRequest() async throws {
        let bookID = UUID()
        let nilProgression = try chatSource(bookID: bookID, id: "nil", progression: nil)
        await #expect(throws: LoreAIError.invalidChatContext) {
            try await rejectingRequestClient().chat(.init(
                bookID: bookID, title: "Livre", stage: .inProgress,
                readFrontierProgression: 0.5,
                excerpts: [.init(text: "Texte", progression: nil, source: nilProgression)],
                question: "Question"
            ))
        }
    }

    @Test func invalidLocatorSourceIsRejectedBeforeRequest() async {
        let bookID = UUID()
        let invalid = LoreAIChatSource(
            id: "invalid", bookID: bookID, label: "Invalide",
            locatorJSON: Data("not-json".utf8), locatorSchemaVersion: 1, progression: 0.2
        )
        await #expect(throws: LoreAIError.invalidChatContext) {
            try await rejectingRequestClient().chat(validContext(bookID: bookID, sources: [invalid]))
        }
    }

    @Test func futureSourceIsRejectedBeforeRequest() async throws {
        let bookID = UUID()
        let future = try chatSource(bookID: bookID, id: "future", progression: 0.8)
        await #expect(throws: LoreAIError.futureReadingContext) {
            try await rejectingRequestClient().chat(validContext(bookID: bookID, sources: [future]))
        }
    }

    @Test func chatRejectsIncompleteAndRefusalResponses() async throws {
        let incomplete = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"status":"incomplete","output_text":"{}"}"#)
        }
        await #expect(throws: LoreAIError.invalidResponse) {
            try await incomplete.chat(.init(title: "Livre", stage: .notStarted, question: "Question"))
        }
        let refusal = makeClient(key: "key") { _ in
            Self.response(status: 200, body: #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"Non"}]}]}"#)
        }
        await #expect(throws: LoreAIError.invalidResponse) {
            try await refusal.chat(.init(title: "Livre", stage: .notStarted, question: "Question"))
        }
    }

    @Test func sourceIdentityAndProgressionUseClosedUnitInterval() throws {
        let bookID = UUID()
        #expect(try chatSource(bookID: bookID, id: "id", progression: 0).hasValidIdentityAndProgression)
        #expect(try chatSource(bookID: bookID, id: "id", progression: 1).hasValidIdentityAndProgression)
        #expect(!(try chatSource(bookID: bookID, id: "id", progression: -0.01)).hasValidIdentityAndProgression)
        #expect(!(try chatSource(bookID: bookID, id: "id", progression: 1.01)).hasValidIdentityAndProgression)
        #expect(!(try chatSource(bookID: bookID, id: "   ", progression: 0.5)).hasValidIdentityAndProgression)
    }

    private func chatSource(
        bookID: UUID,
        id: String,
        progression: Double?,
        text: String = "Texte"
    ) throws -> LoreAIChatSource {
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(totalProgression: progression),
            text: .init(after: "Après", before: "Avant", highlight: text)
        )
        return .init(
            id: id, bookID: bookID, label: "Chapitre",
            locatorJSON: try locator.jsonData(), locatorSchemaVersion: 1, progression: progression
        )
    }

    private func validContext(
        bookID: UUID,
        sources: [LoreAIChatSource],
        text: String = "Texte"
    ) -> LoreAIChatContext {
        .init(
            bookID: bookID, title: "Livre", stage: .inProgress,
            readFrontierProgression: 0.5,
            excerpts: sources.map { .init(text: text, progression: $0.progression, source: $0) },
            question: "Question"
        )
    }

    private func rejectingRequestClient() -> OpenAIResponsesClient {
        makeClient(key: "key") { _ in
            Issue.record("Une source invalide doit être rejetée avant la requête")
            throw URLError(.badServerResponse)
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

    private static func requestBody(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct StubKeyStore: OpenAIAPIKeyStore {
    let key: String?
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String?) throws {}
}

private final class MockURLProtocol: Foundation.URLProtocol, @unchecked Sendable {
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
