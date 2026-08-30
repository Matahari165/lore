import Foundation
import ReadiumShared
import Testing
@testable import Lore

@MainActor
struct ReadingPositionControllerTests {
    @Test func flushSavesLatestLocatorForCurrentBook() async throws {
        let bookID = UUID()
        let store = ProgressStoreSpy()
        let controller = ReadingPositionController(
            bookID: bookID,
            store: store,
            debounceDuration: .seconds(60)
        )
        let locator = makeLocator(progression: 0.64)

        controller.record(locator)
        await controller.flush()

        let saved = store.saved
        #expect(saved?.bookID == bookID)
        #expect(try saved.map { try LocatorJSONCodec.decode($0.data) } == locator)
    }

    @Test func newerLocationReplacesPendingLocation() async throws {
        let store = ProgressStoreSpy()
        let controller = ReadingPositionController(
            bookID: UUID(),
            store: store,
            debounceDuration: .seconds(60)
        )
        let latest = makeLocator(progression: 0.9)

        controller.record(makeLocator(progression: 0.1))
        controller.record(latest)
        await controller.flush()

        let saved = store.saved
        #expect(try saved.map { try LocatorJSONCodec.decode($0.data) } == latest)
    }

    private func makeLocator(progression: Double) -> Locator {
        Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: progression)
        )
    }
}

@MainActor
private final class ProgressStoreSpy: ReaderProgressStore {
    struct Saved: Sendable {
        let data: Data
        let bookID: UUID
    }

    private(set) var saved: Saved?

    func locatorData(for bookID: UUID) throws -> Data? {
        saved?.bookID == bookID ? saved?.data : nil
    }

    func saveLocatorData(_ data: Data, progression: Double?, for bookID: UUID) throws {
        saved = Saved(data: data, bookID: bookID)
    }
}
