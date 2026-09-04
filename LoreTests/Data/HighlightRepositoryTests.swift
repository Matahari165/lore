import Foundation
import ReadiumShared
import SwiftData
import Testing
@testable import Lore

@MainActor
struct HighlightRepositoryTests {
    private enum SaveFailure: Error { case expected }

    @Test func storesListsAndDeletesHighlightForOneBook() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HighlightRecord.self, configurations: configuration)
        let repository = HighlightRepository(context: container.mainContext)
        let bookID = UUID()
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.35),
            text: .init(highlight: "Texte retenu")
        )

        let saved = try repository.addHighlight(
            bookID: bookID,
            locator: locator,
            text: "Texte retenu",
            color: .yellow
        )

        let listed = try repository.highlights(for: bookID)
        #expect(listed.count == 1)
        #expect(listed[0].id == saved.id)
        #expect(listed[0].locator == locator)
        #expect(listed[0].text == "Texte retenu")
        #expect(listed[0].color == .yellow)

        try repository.deleteHighlight(id: saved.id, bookID: bookID)
        #expect(try repository.highlights(for: bookID).isEmpty)
    }

    @Test func filtersHighlightsByBook() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HighlightRecord.self, configurations: configuration)
        let repository = HighlightRepository(context: container.mainContext)
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        let firstBook = UUID()

        _ = try repository.addHighlight(bookID: firstBook, locator: locator, text: "Un", color: .yellow)
        _ = try repository.addHighlight(bookID: UUID(), locator: locator, text: "Deux", color: .yellow)

        #expect(try repository.highlights(for: firstBook).map(\.text) == ["Un"])
    }

    @Test func createsEditsClearsAndPersistsNoteWithoutChangingHighlight() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "LoreHighlightNotes-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: HighlightRecord.self, configurations: configuration)
        let repository = HighlightRepository(context: container.mainContext)
        let bookID = UUID()
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml, locations: .init(progression: 0.42))
        let original = try repository.addHighlight(bookID: bookID, locator: locator, text: "Passage", color: .yellow)
        let originalRecord = try #require(try container.mainContext.fetch(FetchDescriptor<HighlightRecord>()).first)
        let originalLocatorJSON = originalRecord.locatorJSON
        let originalLocatorSchemaVersion = originalRecord.locatorSchemaVersion

        let noted = try repository.updateHighlightNote(id: original.id, bookID: bookID, note: "  Idée personnelle  ")
        #expect(noted.note == "Idée personnelle")
        #expect(noted.id == original.id)
        #expect(noted.bookID == original.bookID)
        #expect(noted.locator == original.locator)
        #expect(noted.text == original.text)
        #expect(noted.createdAt == original.createdAt)
        #expect(noted.color == original.color)
        #expect(originalRecord.locatorJSON == originalLocatorJSON)
        #expect(originalRecord.locatorSchemaVersion == originalLocatorSchemaVersion)

        let reopened = try ModelContainer(for: HighlightRecord.self, configurations: configuration)
        let persisted = try HighlightRepository(context: reopened.mainContext).highlights(for: bookID)
        #expect(persisted.first?.note == "Idée personnelle")

        let cleared = try HighlightRepository(context: reopened.mainContext)
            .updateHighlightNote(id: original.id, bookID: bookID, note: " \n ")
        #expect(cleared.note == nil)
    }

    @Test func noteUpdateCannotCrossBookBoundary() throws {
        let container = try ModelContainer(
            for: HighlightRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = HighlightRepository(context: container.mainContext)
        let bookID = UUID()
        let highlight = try repository.addHighlight(
            bookID: bookID,
            locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
            text: "Passage",
            color: .yellow
        )

        #expect(throws: HighlightStoreError.self) {
            try repository.updateHighlightNote(id: highlight.id, bookID: UUID(), note: "Intrusion")
        }
        #expect(try repository.highlights(for: bookID).first?.note == nil)
    }

    @Test func failedNoteSaveRestoresOnlyPreviousNote() throws {
        let container = try ModelContainer(
            for: HighlightRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let working = HighlightRepository(context: container.mainContext)
        let bookID = UUID()
        let highlight = try working.addHighlight(
            bookID: bookID,
            locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
            text: "Passage",
            color: .yellow
        )
        let originalRecord = try #require(try container.mainContext.fetch(FetchDescriptor<HighlightRecord>()).first)
        let originalLocatorJSON = originalRecord.locatorJSON
        let originalLocatorSchemaVersion = originalRecord.locatorSchemaVersion
        let originalCreatedAt = originalRecord.createdAt
        let failing = HighlightRepository(context: container.mainContext) { _ in throw SaveFailure.expected }

        #expect(throws: SaveFailure.self) {
            try failing.updateHighlightNote(id: highlight.id, bookID: bookID, note: "Perdue")
        }
        #expect(try working.highlights(for: bookID).first?.note == nil)
        let restoredRecord = try #require(try container.mainContext.fetch(FetchDescriptor<HighlightRecord>()).first)
        #expect(restoredRecord.id == highlight.id)
        #expect(restoredRecord.bookID == bookID)
        #expect(restoredRecord.locatorJSON == originalLocatorJSON)
        #expect(restoredRecord.locatorSchemaVersion == originalLocatorSchemaVersion)
        #expect(restoredRecord.text == "Passage")
        #expect(restoredRecord.createdAt == originalCreatedAt)
        #expect(restoredRecord.colorRawValue == HighlightColor.yellow.rawValue)
    }

    @Test func failedDeleteRestoresPersistedHighlight() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HighlightRecord.self, configurations: configuration)
        let workingRepository = HighlightRepository(context: container.mainContext)
        let bookID = UUID()
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        let saved = try workingRepository.addHighlight(
            bookID: bookID,
            locator: locator,
            text: "À conserver",
            color: .yellow
        )
        let failingRepository = HighlightRepository(context: container.mainContext) { _ in
            throw SaveFailure.expected
        }

        #expect(throws: SaveFailure.self) {
            try failingRepository.deleteHighlight(id: saved.id, bookID: bookID)
        }
        #expect(try workingRepository.highlights(for: bookID).map(\.id) == [saved.id])
    }

    @Test func deletingBookDeletesItsHighlightsInSameSave() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BookRecord.self,
            HighlightRecord.self,
            configurations: configuration
        )
        let books = BookRepository(context: container.mainContext)
        let highlights = HighlightRepository(context: container.mainContext)
        let book = BookRecord(
            contentSHA256: String(repeating: "a", count: 64),
            title: "Livre",
            relativeFilePath: "Books/book.epub",
            mediaType: "application/epub+zip"
        )
        try books.add(book)
        _ = try highlights.addHighlight(
            bookID: book.id,
            locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
            text: "Passage",
            color: .yellow
        )

        try books.delete(book)

        #expect(try books.book(id: book.id) == nil)
        #expect(try highlights.highlights(for: book.id).isEmpty)
    }
}
