import Foundation
import Testing
@testable import Lore

struct LibraryAIContextBuilderTests {
    private func input(
        title: String = "Livre",
        status: String = "terminé",
        rating: Int? = 8,
        note: String? = "Note personnelle"
    ) -> LibraryAIBookInput {
        LibraryAIBookInput(
            title: title,
            author: "Auteur",
            status: status,
            progression: 1.0,
            rating: rating,
            readingYear: 2026,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_710_000_000),
            firstReadAt: Date(timeIntervalSince1970: 1_705_000_000),
            lastReadAt: Date(timeIntervalSince1970: 1_709_000_000),
            totalReadingMinutes: 320,
            collections: ["Favoris"],
            highlights: [.init(text: "Passage marquant", note: note, createdAt: Date(timeIntervalSince1970: 1_706_000_000))]
        )
    }

    @Test func finishedBooksComeFirstAndNotesAreKept() throws {
        let context = try LibraryAIContextBuilder.build(
            inputs: [
                input(title: "À lire", status: "à lire", rating: nil, note: nil),
                input(title: "Terminé"),
            ],
            question: "Recommande-moi un livre"
        )
        #expect(context.books.first?.title == "Terminé")
        #expect(context.books.first?.rating == 8)
        #expect(context.books.first?.notes.first?.note == "Note personnelle")
        #expect(context.finishedCount == 1)
    }

    @Test func emptyQuestionOrEmptyLibraryThrows() {
        #expect(throws: LoreAIError.emptyContext) {
            try LibraryAIContextBuilder.build(inputs: [input()], question: "   ")
        }
        #expect(throws: LoreAIError.emptyContext) {
            try LibraryAIContextBuilder.build(inputs: [], question: "Recommande")
        }
    }

    @Test func libraryPromptStaysLocalAndStructured() throws {
        let context = try LibraryAIContextBuilder.build(
            inputs: [input()],
            question: "Que me conseilles-tu ?"
        )
        let prompt = try LoreAILibraryPromptBuilder().prompt(for: context)
        #expect(prompt.developer.contains("bibliothèque personnelle"))
        #expect(prompt.developer.contains("Maximum 6 puces"))
        #expect(prompt.user.contains("Terminé") || prompt.user.contains("Livre"))
        #expect(prompt.user.contains("Que me conseilles-tu"))
    }

    @Test func budgetCoversBooksQuestionAndHistory() throws {
        let longNote = String(repeating: "mot ", count: 200)
        let longPassage = String(repeating: "texte ", count: 200)
        let inputs = (0..<100).map { index in
            LibraryAIBookInput(
                title: "Livre \(index) " + String(repeating: "t", count: 300),
                author: "Auteur",
                status: index % 2 == 0 ? "terminé" : "à lire",
                progression: 1.0,
                rating: 7,
                readingYear: 2026,
                importedAt: nil,
                finishedAt: nil,
                firstReadAt: nil,
                lastReadAt: nil,
                totalReadingMinutes: 120,
                collections: ["C1", "C2"],
                highlights: (0..<10).map { _ in
                    LibraryAIHighlightInput(text: longPassage, note: longNote, createdAt: nil)
                }
            )
        }
        let history = (0..<20).map {
            LoreAIChatMessage(role: $0 % 2 == 0 ? .user : .assistant, text: String(repeating: "h", count: 1_000))
        }
        let context = try LibraryAIContextBuilder.build(
            inputs: inputs,
            question: String(repeating: "q", count: 2_000),
            history: history
        )
        #expect(context.books.count <= 80)
        #expect(context.books.allSatisfy { $0.notes.count <= 5 })
        #expect(context.books.allSatisfy { book in
            book.notes.allSatisfy { ($0.passage?.count ?? 0) <= 300 && ($0.note?.count ?? 0) <= 300 }
        })
        #expect(context.history.count <= 12)
        // Le budget total (livres + question + historique) reste borné : les
        // livres se partagent ce qui reste après question et historique.
        let booksCost = context.books.reduce(0) { total, book in
            total + book.title.count + book.notes.reduce(0) {
                $0 + ($1.passage?.count ?? 0) + ($1.note?.count ?? 0)
            }
        }
        let historyCost = context.history.reduce(0) { $0 + $1.text.count }
        #expect(booksCost + context.question.count + historyCost <= 30_000 + 1_200)
    }

    @Test func libraryChatUsesSharedPrivateModelContract() async throws {
        LibraryMockURLProtocol.handler = { request in
            let body = try Self.requestBody(of: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == OpenAIResponsesConfiguration.model)
            #expect(json["store"] as? Bool == false)
            let input = try #require(json["input"] as? [[String: Any]])
            #expect(input.map { $0["role"] as? String } == ["developer", "user"])
            #expect((input.last?["content"] as? String)?.contains("Livre Partagé") == true)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"output_text":"- Suggestion : lisez ceci.\n\n- Idée essentielle : foncez."}"#.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryMockURLProtocol.self]
        let client = OpenAIResponsesClient(
            keyStore: LibraryStubKeyStore(),
            session: URLSession(configuration: configuration),
            configuration: .init(endpoint: URL(string: "https://example.test/v1/responses")!)
        )
        let context = try LibraryAIContextBuilder.build(
            inputs: [input(title: "Livre Partagé")],
            question: "Que me conseilles-tu ?"
        )
        let answer = try await client.libraryChat(context)
        #expect(answer.contains("Suggestion"))
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

private struct LibraryStubKeyStore: OpenAIAPIKeyStore {
    func loadAPIKey() throws -> String? { "test-key" }
    func saveAPIKey(_ key: String?) throws {}
}

private final class LibraryMockURLProtocol: URLProtocol, @unchecked Sendable {
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
