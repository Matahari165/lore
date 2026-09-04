import Foundation
import ReadiumNavigator
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

    @Test func preferenceUpdateIsPersistedAndSubmittedToReadiumController() throws {
        let controller = ReaderControllerSpy()
        let store = PreferencesStoreSpy(initial: .default)
        let positions = PositionManagerSpy()
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: positions,
            preferencesStore: store
        )
        let updated = ReaderPreferences(
            fontSize: 1.4, typeface: .sansSerif, lineHeight: 1.8, appearance: .dark
        )

        try session.updatePreferences(updated)

        #expect(store.saved == [updated])
        #expect(controller.submittedPreferences.count == 1)
        #expect(controller.submittedPreferences[0].fontSize == 1.4)
        #expect(controller.submittedPreferences[0].publisherStyles == false)
    }

    @Test func chapterNavigationDelegatesTheOriginalReadiumLink() async {
        let origin = makeLocator(0.24)
        let controller = ReaderControllerSpy(currentLocation: origin)
        let chapter = ReaderChapter(
            id: "0:chapter.xhtml", title: "Chapitre", depth: 0,
            link: Link(href: "chapter.xhtml", title: "Chapitre")
        )
        let positions = PositionManagerSpy()
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: positions,
            chapters: [chapter]
        )

        #expect(await session.go(to: chapter))
        #expect(controller.openedLinks.map(\.href) == ["chapter.xhtml"])
        #expect(positions.recordedLocations.isEmpty)
        #expect(await session.goBackAfterJump())
        #expect(controller.openedLocators == [origin])
    }

    @Test func progressionPreviewAndJumpUseLocatedFullLocator() async {
        let origin = makeLocator(0.18)
        let destination = Locator(
            href: URL(string: "part-two.xhtml")!, mediaType: .xhtml,
            title: "Deuxième partie",
            locations: .init(progression: 0.4, totalProgression: 0.62),
            text: .init(after: "après", before: "avant", highlight: "passage")
        )
        let controller = ReaderControllerSpy(currentLocation: origin)
        let positions = PositionManagerSpy()
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: positions,
            progressionLocator: { value in value == 0.62 ? destination : nil }
        )
        var historyStates: [Bool] = []
        session.setNavigationHistoryHandler { historyStates.append($0) }

        let preview = await session.previewNavigation(at: 0.62)
        #expect(preview == ReaderNavigationPreview(
            progression: 0.62,
            chapterTitle: "Deuxième partie",
            isAvailable: true
        ))
        #expect(await session.go(toProgression: 0.62))
        #expect(controller.openedLocators == [destination])
        #expect(positions.recordedLocations == [destination])
        #expect(historyStates == [false, true])

        #expect(await session.goBackAfterJump())
        #expect(controller.openedLocators == [destination, origin])
        #expect(positions.recordedLocations == [destination, origin])
        #expect(historyStates == [false, true, false])
    }

    @Test func failedJumpDoesNotCreateBackHistory() async {
        let controller = ReaderControllerSpy(currentLocation: makeLocator(0.3), navigationSucceeds: false)
        let destination = makeLocator(0.8)
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: PositionManagerSpy(),
            progressionLocator: { _ in destination }
        )
        var historyStates: [Bool] = []
        session.setNavigationHistoryHandler { historyStates.append($0) }

        #expect(await session.go(toProgression: 0.8) == false)
        #expect(await session.goBackAfterJump() == false)
        #expect(historyStates == [false])
    }

    @Test func progressionSubscriptionImmediatelyPublishesCurrentLocator() {
        let session = ReaderSessionController(
            locationProvider: LocationProviderSpy(locator: makeLocator(0.42)),
            positionController: PositionManagerSpy()
        )
        var received: [Double] = []

        session.setProgressionHandler { received.append($0) }

        #expect(received == [0.42])
    }

    @Test func validatedCitationNavigatesToItsExactLocator() async throws {
        let bookID = UUID()
        let controller = ReaderControllerSpy(currentLocation: makeLocator(0.6))
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: PositionManagerSpy(),
            citationBookID: bookID,
            citationReadingOrder: [Link(href: "chapter.xhtml")]
        )
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(totalProgression: 0.4),
            text: .init(highlight: "Passage exact")
        )
        let source = LoreAIChatSource(
            id: "opaque", bookID: bookID, label: "Passage",
            locatorJSON: try locator.jsonData(), locatorSchemaVersion: 1, progression: 0.4
        )

        #expect(await session.go(to: source))
        #expect(controller.openedLocators == [locator])
    }

    @Test(arguments: [(-0.01, "opaque"), (1.01, "opaque"), (0.4, "   ")])
    func invalidCitationIdentityNeverNavigates(_ progression: Double, _ id: String) async throws {
        let bookID = UUID()
        let controller = ReaderControllerSpy(currentLocation: makeLocator(1))
        let session = ReaderSessionController(
            locationProvider: controller,
            positionController: PositionManagerSpy(),
            citationBookID: bookID,
            citationReadingOrder: [Link(href: "chapter.xhtml")]
        )
        let locator = makeLocator(progression)
        let source = LoreAIChatSource(
            id: id, bookID: bookID, label: "Passage",
            locatorJSON: try locator.jsonData(), locatorSchemaVersion: 1, progression: progression
        )
        #expect(await !session.go(to: source))
        #expect(controller.openedLocators.isEmpty)
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
private final class ReaderControllerSpy: EPUBReaderControlling {
    var currentLocation: Locator?
    let viewController = UIViewController()
    let navigationSucceeds: Bool
    private(set) var submittedPreferences: [EPUBPreferences] = []
    private(set) var openedLinks: [Link] = []
    private(set) var openedLocators: [Locator] = []

    init(currentLocation: Locator? = nil, navigationSucceeds: Bool = true) {
        self.currentLocation = currentLocation
        self.navigationSucceeds = navigationSucceeds
    }

    func submitPreferences(_ preferences: EPUBPreferences) {
        submittedPreferences.append(preferences)
    }

    func go(to link: Link, options: NavigatorGoOptions) async -> Bool {
        openedLinks.append(link)
        return navigationSucceeds
    }

    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool {
        openedLocators.append(locator)
        if navigationSucceeds { currentLocation = locator }
        return navigationSucceeds
    }
}

@MainActor
private final class PreferencesStoreSpy: ReaderPreferencesStoring {
    let initial: ReaderPreferences
    private(set) var saved: [ReaderPreferences] = []
    init(initial: ReaderPreferences) { self.initial = initial }
    func load() -> ReaderPreferences { initial }
    func save(_ preferences: ReaderPreferences) throws { saved.append(preferences) }
}

@MainActor
private final class PositionManagerSpy: ReadingPositionManaging {
    enum Failure: Error { case save }
    var failuresRemaining: Int
    private(set) var flushLocations: [Locator?] = []
    private(set) var recordedLocations: [Locator] = []
    private(set) var successfulFlushes = 0
    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }
    func record(_ locator: Locator) { recordedLocations.append(locator) }
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
