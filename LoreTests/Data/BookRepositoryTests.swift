import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct BookRepositoryTests {
    @Test func storesBooksAndReturnsNewestFirst() throws {
        let repository = try makeRepository()
        let older = BookRecord(
            title: "Older",
            relativeFilePath: "Books/older/book.epub",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = BookRecord(
            title: "Newer",
            relativeFilePath: "Books/newer/book.epub",
            importedAt: Date(timeIntervalSince1970: 2)
        )

        try repository.add(older)
        try repository.add(newer)

        #expect(try repository.books().map(\.title) == ["Newer", "Older"])
    }

    @Test func savesCompleteLocatorForOnlyTheRequestedBook() throws {
        let repository = try makeRepository()
        let first = BookRecord(title: "First", relativeFilePath: "Books/1/book.epub")
        let second = BookRecord(title: "Second", relativeFilePath: "Books/2/book.epub")
        try repository.add(first)
        try repository.add(second)
        let locator = Data(#"{"href":"chapter.xhtml","locations":{"progression":0.42}}"#.utf8)

        try repository.saveProgress(
            for: first.id, locatorJSON: locator, locatorSchemaVersion: 1, progression: 1.4
        )

        #expect(try repository.book(id: first.id)?.lastLocatorJSON == locator)
        #expect(try repository.book(id: first.id)?.lastProgression == 1)
        #expect(try repository.book(id: first.id)?.locatorSchemaVersion == 1)
        #expect(try repository.book(id: second.id)?.lastLocatorJSON == nil)
    }

    @Test func rejectsProgressForMissingBook() throws {
        let repository = try makeRepository()

        #expect(throws: BookRepositoryError.bookNotFound) {
            try repository.saveProgress(
                for: UUID(),
                locatorJSON: Data("{}".utf8),
                locatorSchemaVersion: 1,
                progression: nil
            )
        }
    }

    @Test func failedInsertIsRemovedFromTheContext() throws {
        enum Expected: Error { case save }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BookRecord.self, configurations: configuration)
        let repository = BookRepository(context: container.mainContext) { _ in throw Expected.save }
        let book = BookRecord(title: "Unsaved", relativeFilePath: "")

        #expect(throws: Expected.self) { try repository.add(book) }
        #expect(try repository.books().isEmpty)
    }

    private func makeRepository() throws -> BookRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BookRecord.self, configurations: configuration)
        return BookRepository(context: container.mainContext)
    }
}
