import Foundation
import ReadiumShared
import Testing
@testable import Lore

@MainActor
struct ReadingPositionControllerTests {
    @Test func flushSavesLatestLocatorForCurrentBook() async throws {
        let bookID = UUID(), store = ProgressStoreSpy()
        let controller = ReadingPositionController(bookID: bookID, store: store, debounceDuration: .seconds(60))
        let locator = makeLocator(progression: 0.64)
        controller.record(locator)
        try await controller.flush()
        #expect(store.saved.last?.bookID == bookID)
        #expect(try store.saved.last.map { try LocatorPersistenceCodec.decode($0.stored).locator } == locator)
    }

    @Test func storeFailureKeepsPendingLocatorForRetry() async throws {
        let store = ProgressStoreSpy(failuresRemaining: 1)
        let controller = ReadingPositionController(bookID: UUID(), store: store, debounceDuration: .seconds(60))
        let locator = makeLocator(progression: 0.4)
        controller.record(locator)
        await #expect(throws: ProgressStoreSpy.Failure.self) { try await controller.flush() }
        try await controller.flush()
        #expect(store.attempts == 2)
        #expect(try LocatorPersistenceCodec.decode(store.saved[0].stored).locator == locator)
    }

    @Test func successfulFlushClearsPendingAndDoesNotRewrite() async throws {
        let store = ProgressStoreSpy()
        let controller = ReadingPositionController(bookID: UUID(), store: store, debounceDuration: .seconds(60))
        controller.record(makeLocator(progression: 0.2))
        try await controller.flush()
        try await controller.flush()
        #expect(store.attempts == 1)
    }

    @Test func debounceFailureIsReportedAndRemainsRetryable() async throws {
        let store = ProgressStoreSpy(failuresRemaining: 1)
        let (errors, errorContinuation) = AsyncStream<Void>.makeStream()
        let controller = ReadingPositionController(
            bookID: UUID(), store: store, debounceDuration: .zero,
            sleep: { _ in }, onError: { _ in errorContinuation.yield() }
        )
        controller.record(makeLocator(progression: 0.7))
        var errorIterator = errors.makeAsyncIterator()
        await errorIterator.next()
        errorContinuation.finish()
        try await controller.flush()
        #expect(store.attempts == 2)
    }

    @Test func explicitCurrentLocationIsSavedForBackgroundOrClose() async throws {
        let store = ProgressStoreSpy()
        let controller = ReadingPositionController(bookID: UUID(), store: store, debounceDuration: .seconds(60))
        let current = makeLocator(progression: 0.95)
        try await controller.flush(currentLocator: current)
        #expect(try LocatorPersistenceCodec.decode(store.saved[0].stored).locator == current)
    }

    @Test func explicitOlderLocationCannotReplacePendingObservedLocation() async throws {
        let store = ProgressStoreSpy()
        let controller = ReadingPositionController(bookID: UUID(), store: store, debounceDuration: .seconds(60))
        let latestObserved = makeLocator(progression: 0.91)
        let staleProviderLocation = makeLocator(progression: 0.24)

        controller.record(latestObserved)
        try await controller.flush(currentLocator: staleProviderLocation)
        try await controller.flush(currentLocator: staleProviderLocation)

        #expect(store.saved.count == 1)
        let decoded = try store.saved.map { try LocatorPersistenceCodec.decode($0.stored).locator }
        #expect(decoded == [latestObserved])
    }

    private func makeLocator(progression: Double) -> Locator {
        Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }
}

@MainActor
private final class ProgressStoreSpy: ReaderProgressStore {
    enum Failure: Error { case save }
    struct Saved { let stored: StoredLocator; let bookID: UUID; let progression: Double? }
    var failuresRemaining: Int
    private(set) var attempts = 0
    private(set) var saved: [Saved] = []

    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }
    func storedLocator(for bookID: UUID) throws -> StoredLocator? { saved.last?.stored }
    func saveLocator(_ stored: StoredLocator, progression: Double?, for bookID: UUID) throws {
        attempts += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure.save
        }
        saved.append(Saved(stored: stored, bookID: bookID, progression: progression))
    }
}
