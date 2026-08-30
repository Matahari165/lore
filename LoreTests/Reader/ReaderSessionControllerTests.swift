import Foundation
import ReadiumShared
import Testing
import UIKit
@testable import Lore

@MainActor
struct ReaderSessionControllerTests {
    @Test func backgroundFailureRetriesPendingPositionWhenActive() async throws {
        let locator = makeLocator(0.6)
        let positions = PositionManagerSpy(failuresRemaining: 1)
        let session = ReaderSessionController(
            locationProvider: LocationProviderSpy(locator: locator),
            positionController: positions
        )

        await #expect(throws: PositionManagerSpy.Failure.self) {
            try await session.handleLifecycle(.background)
        }
        try await session.handleLifecycle(.active)

        #expect(positions.flushLocations.count == 2)
        #expect(positions.flushLocations[0] == locator)
        #expect(positions.flushLocations[1] == nil)
        #expect(positions.successfulFlushes == 1)
    }

    @Test func lifecycleAndClosePassTheExpectedCurrentLocation() async throws {
        let locator = makeLocator(0.8)
        let positions = PositionManagerSpy()
        let session = ReaderSessionController(
            locationProvider: LocationProviderSpy(locator: locator),
            positionController: positions
        )

        try await session.handleLifecycle(.inactive)
        try await session.handleLifecycle(.background)
        try await session.handleLifecycle(.active)
        try await session.close()

        #expect(positions.flushLocations == [locator, locator, nil, locator])
    }

    @Test func closePropagatesStoreFailureAndReportsIt() async {
        let positions = PositionManagerSpy(failuresRemaining: 1)
        var reportedErrors = 0
        let session = ReaderSessionController(
            locationProvider: LocationProviderSpy(locator: makeLocator(0.2)),
            positionController: positions,
            onError: { _ in reportedErrors += 1 }
        )

        await #expect(throws: PositionManagerSpy.Failure.self) { try await session.close() }
        #expect(reportedErrors == 1)
    }

    @Test func corruptStoredLocatorProducesNilInitialLocationAndReportsError() {
        let store = CorruptLocatorStore()
        var reported: Error?

        let restored = ReaderSessionController.restoreInitialLocation(
            bookID: UUID(), store: store, onError: { reported = $0 }
        )

        #expect(restored.locator == nil)
        #expect(!restored.requiresRewrite)
        #expect(reported is ReaderError)
        #expect(store.saveAttempts == 0)
    }

    private func makeLocator(_ progression: Double) -> Locator {
        Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(totalProgression: progression)
        )
    }
}

@MainActor
private final class LocationProviderSpy: ReaderLocationProviding {
    let currentLocation: Locator?
    let viewController = UIViewController()
    init(locator: Locator?) { currentLocation = locator }
}

@MainActor
private final class PositionManagerSpy: ReadingPositionManaging {
    enum Failure: Error { case save }
    var failuresRemaining: Int
    private(set) var flushLocations: [Locator?] = []
    private(set) var successfulFlushes = 0
    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }
    func record(_ locator: Locator) {}
    func flush(currentLocator: Locator?) async throws {
        flushLocations.append(currentLocator)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure.save
        }
        successfulFlushes += 1
    }
}

@MainActor
private final class CorruptLocatorStore: ReaderProgressStore {
    private(set) var saveAttempts = 0
    func storedLocator(for bookID: UUID) throws -> StoredLocator? {
        StoredLocator(data: Data("not-json".utf8), schemaVersion: 1)
    }
    func saveLocator(_ stored: StoredLocator, progression: Double?, for bookID: UUID) throws {
        saveAttempts += 1
    }
}
