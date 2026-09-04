import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct LibraryViewModelTests {
    @Test func resumeQueueUsesRealActivityAndKeepsOnlyFourActiveBooks() throws {
        let fixture = try LibraryViewModelFixture()
        let baseDate = Date(timeIntervalSince1970: 1_000)
        var books: [BookRecord] = []

        for index in 0..<6 {
            let book = BookRecord(
                title: "En cours \(index)",
                relativeFilePath: "Books/\(UUID().uuidString)/book.epub",
                lastLocatorJSON: Data("{}".utf8),
                lastProgression: Double(index + 1) / 10,
                progressUpdatedAt: baseDate.addingTimeInterval(Double(index * 60))
            )
            try fixture.repository.add(book)
            books.append(book)
        }

        // The session date is the real activity signal and must outrank a more
        // recent imported progress timestamp when the two disagree.
        try fixture.recordActivity(for: books[1].id, at: baseDate.addingTimeInterval(3_600))
        try fixture.recordActivity(for: books[3].id, at: baseDate.addingTimeInterval(1_800))

        let model = fixture.makeModel()

        #expect(model.resumableBooks.count == 4)
        #expect(model.resumableBooks.map(\.title) == [
            "En cours 1", "En cours 3", "En cours 5", "En cours 4"
        ])
        #expect(model.recentActivityDate(for: books[1]) == baseDate.addingTimeInterval(3_600))
    }

    @Test func finishedAndUnreadBooksDoNotEnterAnEmptyResumeQueue() throws {
        let fixture = try LibraryViewModelFixture()
        let finished = BookRecord(
            title: "Terminé",
            relativeFilePath: "Books/finished/book.epub",
            lastLocatorJSON: Data("{}".utf8),
            lastProgression: 1,
            finishedAt: Date(timeIntervalSince1970: 2_000)
        )
        let unread = BookRecord(
            title: "À lire",
            relativeFilePath: "Books/unread/book.epub"
        )
        try fixture.repository.add(finished)
        try fixture.repository.add(unread)

        let model = fixture.makeModel()

        #expect(model.resumableBooks.isEmpty)
        #expect(model.visibleBooks.map(\.title).count == 2)
        #expect(model.visibleBooks.contains(where: { $0.readingStatus == .finished }))
        #expect(model.visibleBooks.contains(where: { $0.readingStatus == .toRead }))
    }

    @Test func hiddenBookLeavesResumeButKeepsItsLibraryStatus() throws {
        let fixture = try LibraryViewModelFixture()
        let book = BookRecord(
            title: "Masqué de Reprendre",
            relativeFilePath: "Books/hidden/book.epub",
            lastLocatorJSON: Data("{}".utf8),
            lastProgression: 0.35,
            isHiddenFromResume: true
        )
        try fixture.repository.add(book)

        let model = fixture.makeModel()

        #expect(model.resumableBooks.isEmpty)
        #expect(model.visibleBooks.map(\.id) == [book.id])
        #expect(model.visibleBooks.first?.lastProgression == 0.35)
    }

    @Test func smartAndManualCollectionsReferenceExistingBooks() throws {
        let fixture = try LibraryViewModelFixture()
        let active = BookRecord(
            title: "Active", author: " Ada ", relativeFilePath: "active.epub",
            lastLocatorJSON: Data("{}".utf8), lastProgression: 0.2
        )
        let finished = BookRecord(
            title: "Finished", author: "Ada", relativeFilePath: "finished.epub",
            finishedAt: .now, readingYear: 2026
        )
        try fixture.repository.add(active)
        try fixture.repository.add(finished)
        let collection = try fixture.repository.createCollection(named: "Favoris")
        try fixture.repository.setMembership(true, bookID: active.id, collectionID: collection.id)

        let model = fixture.makeModel()

        #expect(model.books(in: .inProgress).map(\.id) == [active.id])
        #expect(model.books(in: .year(2026)).map(\.id) == [finished.id])
        #expect(model.books(in: .author("Ada")).count == 2)
        #expect(model.books(in: collection).map(\.id) == [active.id])
        #expect(model.books(in: collection).first === active)
    }

    @Test func recentCollectionKeepsNewestFirstAndLimitsResults() throws {
        let fixture = try LibraryViewModelFixture()
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<13 {
            try fixture.repository.add(BookRecord(
                title: "Livre \(index)",
                relativeFilePath: "book-\(index).epub",
                importedAt: origin.addingTimeInterval(Double(index))
            ))
        }

        let recent = fixture.makeModel().books(in: .recent)

        #expect(recent.count == 12)
        #expect(recent.map(\.title).first == "Livre 12")
        #expect(recent.map(\.title).last == "Livre 1")
    }
}

@MainActor
private final class LibraryViewModelFixture {
    let container: ModelContainer
    let repository: BookRepository
    let sessionRepository: ReadingSessionRepository
    private let fileStore: BookFileStore

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: BookRecord.self,
            ReadingSessionRecord.self,
            HighlightRecord.self,
            ManualCollectionRecord.self,
            CollectionMembershipRecord.self,
            configurations: configuration
        )
        repository = BookRepository(context: container.mainContext)
        sessionRepository = ReadingSessionRepository(context: container.mainContext)
        fileStore = try BookFileStore(
            applicationSupportURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("Lore-LibraryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    func recordActivity(for bookID: UUID, at date: Date) throws {
        let sessionID = try sessionRepository.begin(bookID: bookID, at: date.addingTimeInterval(-30))
        try sessionRepository.recordActivity(sessionID: sessionID, at: date)
        try sessionRepository.finish(sessionID: sessionID, at: date)
    }

    func makeModel() -> LibraryViewModel {
        LibraryViewModel(
            repository: repository,
            sessionRepository: sessionRepository,
            fileStore: fileStore,
            publicationService: ReadiumPublicationService()
        )
    }

}
