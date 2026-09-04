import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct BookRepositoryTests {
    @Test func storesBooksAndReturnsNewestFirst() throws {
        let fixture = try makeRepository()
        let repository = fixture.repository
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
        let fixture = try makeRepository()
        let repository = fixture.repository
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
        let fixture = try makeRepository()
        let repository = fixture.repository

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
        let container = try ModelContainer(
            for: BookRecord.self, ManualCollectionRecord.self, CollectionMembershipRecord.self,
            configurations: configuration
        )
        let repository = BookRepository(context: container.mainContext) { _ in throw Expected.save }
        let book = BookRecord(title: "Unsaved", relativeFilePath: "")

        #expect(throws: Expected.self) { try repository.add(book) }
        #expect(try repository.books().isEmpty)
    }

    @Test func derivesPersistentReadingCategoriesFromSavedProgressAndCompletion() {
        let unread = BookRecord(title: "Unread", relativeFilePath: "unread.epub")
        let active = BookRecord(
            title: "Active",
            relativeFilePath: "active.epub",
            lastLocatorJSON: Data("{}".utf8),
            lastProgression: 0.25
        )
        let finished = BookRecord(
            title: "Finished",
            relativeFilePath: "finished.epub",
            finishedAt: Date(timeIntervalSince1970: 10)
        )

        #expect(unread.readingStatus == .toRead)
        #expect(active.readingStatus == .inProgress)
        #expect(finished.readingStatus == .finished)
    }

    @Test func marksABookFinishedAndRestoresItsPreviousReadingCategory() throws {
        let fixture = try makeRepository()
        let repository = fixture.repository
        let book = BookRecord(
            title: "Lecture",
            relativeFilePath: "book.epub",
            lastLocatorJSON: Data("{}".utf8),
            lastProgression: 0.4
        )
        try repository.add(book)
        let finishedAt = Date(timeIntervalSince1970: 100)

        try repository.setFinished(true, for: book.id, at: finishedAt)
        #expect(book.finishedAt == finishedAt)
        #expect(book.readingStatus == .finished)

        try repository.setFinished(false, for: book.id)
        #expect(book.finishedAt == nil)
        #expect(book.readingStatus == .inProgress)
    }

    @Test func hidingFromResumePreservesProgress() throws {
        let fixture = try makeRepository()
        let repository = fixture.repository
        let locator = Data(#"{"href":"chapter.xhtml"}"#.utf8)
        let book = BookRecord(
            title: "Lecture",
            relativeFilePath: "book.epub",
            lastLocatorJSON: locator,
            lastProgression: 0.4
        )
        try repository.add(book)

        try repository.setHiddenFromResume(true, for: book.id)

        #expect(book.isHiddenFromResume)
        #expect(book.lastLocatorJSON == locator)
        #expect(book.lastProgression == 0.4)
        #expect(book.readingStatus == .inProgress)
    }

    @Test func manualMembershipIsUniqueAndDoesNotDuplicateTheBook() throws {
        let fixture = try makeRepository()
        let book = BookRecord(title: "Unique", relativeFilePath: "book.epub")
        try fixture.repository.add(book)
        let collection = try fixture.repository.createCollection(named: "Essais")

        try fixture.repository.setMembership(true, bookID: book.id, collectionID: collection.id)
        try fixture.repository.setMembership(true, bookID: book.id, collectionID: collection.id)

        #expect(try fixture.repository.books().count == 1)
        #expect(try fixture.repository.collectionMemberships().count == 1)
        #expect(try fixture.repository.collectionMemberships().first?.bookID == book.id)

        try fixture.repository.setMembership(false, bookID: book.id, collectionID: collection.id)
        try fixture.repository.setMembership(false, bookID: book.id, collectionID: collection.id)
        #expect(try fixture.repository.collectionMemberships().isEmpty)
    }

    @Test func membershipRejectsMissingBookOrCollection() throws {
        let fixture = try makeRepository()
        let book = BookRecord(title: "Présent", relativeFilePath: "book.epub")
        try fixture.repository.add(book)
        let collection = try fixture.repository.createCollection(named: "Présente")

        #expect(throws: BookRepositoryError.bookNotFound) {
            try fixture.repository.setMembership(true, bookID: UUID(), collectionID: collection.id)
        }
        #expect(throws: BookRepositoryError.collectionNotFound) {
            try fixture.repository.setMembership(true, bookID: book.id, collectionID: UUID())
        }
        #expect(try fixture.repository.collectionMemberships().isEmpty)
    }

    @Test func deletingCollectionOrBookOnlyCleansMemberships() throws {
        let fixture = try makeRepository()
        let first = BookRecord(title: "First", relativeFilePath: "Books/first/book.epub")
        let second = BookRecord(title: "Second", relativeFilePath: "Books/second/book.epub")
        try fixture.repository.add(first)
        try fixture.repository.add(second)
        let collection = try fixture.repository.createCollection(named: "À garder")
        try fixture.repository.setMembership(true, bookID: first.id, collectionID: collection.id)
        try fixture.repository.setMembership(true, bookID: second.id, collectionID: collection.id)

        try fixture.repository.delete(first)
        #expect(try fixture.repository.books().map(\.id) == [second.id])
        #expect(try fixture.repository.collectionMemberships().map(\.bookID) == [second.id])

        try fixture.repository.deleteCollection(collection)
        #expect(try fixture.repository.books().map(\.id) == [second.id])
        #expect(try fixture.repository.collectionMemberships().isEmpty)
    }

    @Test func additiveCollectionSchemaReopensAnExistingPersistentStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lore-CollectionMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Lore.store")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let oldConfiguration = ModelConfiguration(url: storeURL)
            let oldContainer = try ModelContainer(for: BookRecord.self, configurations: oldConfiguration)
            oldContainer.mainContext.insert(BookRecord(title: "Avant migration", relativeFilePath: "book.epub"))
            try oldContainer.mainContext.save()
        }

        let migratedConfiguration = ModelConfiguration(url: storeURL)
        let migrated = try ModelContainer(
            for: BookRecord.self, ManualCollectionRecord.self, CollectionMembershipRecord.self,
            configurations: migratedConfiguration
        )
        let repository = BookRepository(context: migrated.mainContext)
        #expect(try repository.books().map(\.title) == ["Avant migration"])
        #expect(try repository.collections().isEmpty)
    }

    private func makeRepository() throws -> RepositoryFixture {
        try RepositoryFixture()
    }
}

@MainActor
private final class RepositoryFixture {
    let container: ModelContainer
    let repository: BookRepository

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: BookRecord.self, ManualCollectionRecord.self, CollectionMembershipRecord.self,
            configurations: configuration
        )
        repository = BookRepository(context: container.mainContext)
    }
}
