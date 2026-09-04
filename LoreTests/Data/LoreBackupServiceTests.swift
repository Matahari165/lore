import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct LoreBackupServiceTests {
    @Test func mergeIsIdempotentAndNeverOverwritesAConflictingBook() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let bookID = UUID()
        let payload = fixture.payload(bookID: bookID, digest: String(repeating: "a", count: 64))

        let first = try fixture.service.merge(payload: payload)
        let second = try fixture.service.merge(payload: payload)
        #expect(first.insertedBooks == 1)
        #expect(second.insertedBooks == 0)
        #expect(try fixture.context.fetch(FetchDescriptor<BookRecord>()).count == 1)

        let conflict = fixture.payload(bookID: bookID, digest: String(repeating: "b", count: 64))
        #expect(throws: LoreBackupError.conflictingBook(bookID)) {
            _ = try fixture.service.merge(payload: conflict)
        }
    }

    @Test func rejectsInvalidRatingLocatorAndOrphanChildBeforeMutation() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let bookID = UUID()
        let invalidBook = fixture.book(id: bookID, digest: nil, rating: 11)
        let orphan = LoreBackupPayload.Session(
            id: UUID(), bookID: UUID(), startedAt: .now, lastActivityAt: .now, endedAt: nil
        )
        let payload = LoreBackupPayload(
            formatVersion: 1, createdAt: .now, books: [invalidBook], sessions: [orphan], highlights: [], vocabulary: [], podcasts: [], collections: [], collectionMemberships: []
        )

        #expect(throws: LoreBackupError.self) { _ = try fixture.service.merge(payload: payload) }
        #expect(try fixture.context.fetch(FetchDescriptor<BookRecord>()).isEmpty)
    }

    @Test func exportManifestReportsCountsAndMissingEPUBsAndExcludesAIModels() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let missingBook = BookRecord(title: "Sans fichier", relativeFilePath: "")
        fixture.context.insert(missingBook)
        try fixture.context.save()
        let package = fixture.root.appendingPathComponent("Backup.lorebackup")

        try fixture.service.exportBackup(to: package)

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            LoreBackupManifest.self,
            from: Data(contentsOf: package.appendingPathComponent(LoreBackupService.manifestFileName))
        )
        #expect(manifest.recordCounts["books"] == 1)
        #expect(manifest.missingEPUBBookIDs == [missingBook.id])
        #expect(manifest.recordCounts.keys.sorted() == ["books", "collectionMemberships", "collections", "highlights", "podcasts", "sessions", "vocabulary"])
    }

    @Test func exportedEPUBRestoresAndASecondRestoreIsANoOp() throws {
        let source = try Fixture(); defer { source.cleanup() }
        let epubSource = source.root.appendingPathComponent("source.epub")
        try Data("epub-test".utf8).write(to: epubSource)
        let staged = try source.fileStore.stageEPUB(from: epubSource)
        let book = BookRecord(contentSHA256: staged.contentSHA256, title: "Livre", relativeFilePath: "")
        book.relativeFilePath = try source.fileStore.promote(staged, to: book.id)
        source.context.insert(book)
        try source.context.save()
        let package = source.root.appendingPathComponent("Backup.lorebackup")
        try source.service.exportBackup(to: package)

        let destination = try Fixture(); defer { destination.cleanup() }
        let first = try destination.service.restoreBackup(from: package)
        let second = try destination.service.restoreBackup(from: package)

        #expect(first.insertedBooks == 1)
        #expect(first.restoredEPUBs == 1)
        #expect(second.insertedBooks == 0)
        #expect(second.restoredEPUBs == 0)
        let restored = try #require(destination.context.fetch(FetchDescriptor<BookRecord>()).first)
        #expect(try Data(contentsOf: destination.fileStore.fileURL(for: restored.relativeFilePath)) == Data("epub-test".utf8))
    }

    @Test func podcastAndCollectionsRoundTripWithoutAIData() throws {
        let source = try Fixture(); defer { source.cleanup() }
        let mp4 = source.root.appendingPathComponent("episode.mp4")
        try Data("mp4-test".utf8).write(to: mp4)
        let staged = try source.podcastFileStore.stageMP4(from: mp4)
        let podcast = PodcastRecord(contentSHA256: staged.contentSHA256, title: "Episode", originalFilename: "episode.mp4", relativeFilePath: "")
        podcast.relativeFilePath = try source.podcastFileStore.promote(staged, to: podcast.id)
        let book = BookRecord(title: "Livre", relativeFilePath: "")
        let collection = ManualCollectionRecord(name: "Favoris", normalizedName: "favoris")
        source.context.insert(book)
        source.context.insert(podcast)
        source.context.insert(collection)
        source.context.insert(CollectionMembershipRecord(collectionID: collection.id, bookID: book.id))
        try source.context.save()
        let package = source.root.appendingPathComponent("Complete.lorebackup")
        try source.service.exportBackup(to: package)

        let destination = try Fixture(); defer { destination.cleanup() }
        let report = try destination.service.restoreBackup(from: package)
        #expect(report.insertedPodcasts == 1)
        #expect(report.restoredPodcasts == 1)
        #expect(report.insertedCollections == 1)
        #expect(report.insertedCollectionMemberships == 1)
        #expect(try destination.context.fetch(FetchDescriptor<PodcastRecord>()).count == 1)
        #expect(try destination.context.fetch(FetchDescriptor<AIConversationRecord>()).isEmpty)
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let container: ModelContainer
        let context: ModelContext
        let fileStore: BookFileStore
        let podcastFileStore: PodcastFileStore
        let service: LoreBackupService

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            container = try ModelContainer(
                for: BookRecord.self, ReadingSessionRecord.self, HighlightRecord.self, VocabularyRecord.self, PodcastRecord.self, ManualCollectionRecord.self, CollectionMembershipRecord.self, AIConversationRecord.self, AIMessageRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
            fileStore = try BookFileStore(applicationSupportURL: root)
            podcastFileStore = try PodcastFileStore(applicationSupportURL: root)
            service = LoreBackupService(context: context, fileStore: fileStore, podcastFileStore: podcastFileStore)
        }

        func payload(bookID: UUID, digest: String?) -> LoreBackupPayload {
            LoreBackupPayload(formatVersion: 1, createdAt: .now, books: [book(id: bookID, digest: digest)], sessions: [], highlights: [], vocabulary: [], podcasts: [], collections: [], collectionMemberships: [])
        }

        func book(id: UUID, digest: String?, rating: Int? = nil) -> LoreBackupPayload.Book {
            .init(id: id, contentSHA256: digest, title: "Livre", author: nil, coverData: nil,
                  mediaType: "application/epub+zip", importedAt: .now, lastLocatorJSON: nil,
                  lastProgression: nil, progressUpdatedAt: nil, locatorSchemaVersion: nil,
                  finishedAt: nil, rating: rating, readingYear: nil, isHiddenFromResume: false)
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
