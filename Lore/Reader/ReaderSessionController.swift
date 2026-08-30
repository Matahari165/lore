import Foundation
import ReadiumNavigator
@preconcurrency import ReadiumShared
import UIKit

@MainActor
final class ReaderSessionController {
    let contentViewController: UIViewController
    let chapters: [ReaderChapter]
    private(set) var preferences: ReaderPreferences

    private let publication: Publication?
    private let locationProvider: any ReaderLocationProviding
    private let readerController: (any EPUBReaderControlling)?
    private let positionController: any ReadingPositionManaging
    private let readingActivity: any ReadingActivityManaging
    private let preferencesStore: any ReaderPreferencesStoring
    private let navigatorDelegate: ReaderNavigatorDelegate?
    private let directionalNavigationAdapter: DirectionalNavigationAdapter?
    private let onError: @MainActor (Error) -> Void

    static func make(
        bookID: UUID,
        fileURL: URL,
        publicationService: ReadiumPublicationService,
        progressStore: any ReaderProgressStore,
        readingActivity: any ReadingActivityManaging,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) async throws -> ReaderSessionController {
        let opened = try await publicationService.openEPUB(at: fileURL)
        let preferencesStore = UserDefaultsReaderPreferencesStore()
        let preferences = preferencesStore.load()
        let chapters: [ReaderChapter]
        do {
            nonisolated(unsafe) let publication = opened.publication
            chapters = ReaderChapter.flatten(try await publication.tableOfContents().get())
        } catch {
            chapters = []
            onError(error)
        }

        let restoration = restoreInitialLocation(bookID: bookID, store: progressStore, onError: onError)

        let session = try ReaderSessionController(
            bookID: bookID,
            publication: opened.publication,
            initialLocation: restoration.locator,
            progressStore: progressStore,
            readingActivity: readingActivity,
            preferences: preferences,
            preferencesStore: preferencesStore,
            chapters: chapters,
            onError: onError
        )
        if restoration.requiresRewrite, let initialLocation = restoration.locator {
            session.positionController.record(initialLocation)
        }
        return session
    }

    init(
        bookID: UUID,
        publication: Publication,
        initialLocation: Locator?,
        progressStore: any ReaderProgressStore,
        readingActivity: any ReadingActivityManaging,
        preferences: ReaderPreferences,
        preferencesStore: any ReaderPreferencesStoring,
        chapters: [ReaderChapter],
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) throws {
        self.publication = publication
        self.preferences = preferences
        self.preferencesStore = preferencesStore
        self.chapters = chapters
        self.onError = onError

        let positionController = ReadingPositionController(
            bookID: bookID,
            store: progressStore,
            onError: onError
        )
        self.positionController = positionController
        self.readingActivity = readingActivity

        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation,
            config: .init(preferences: preferences.readiumValue)
        )
        locationProvider = navigator
        readerController = navigator
        contentViewController = navigator

        let delegate = ReaderNavigatorDelegate(
            positionController: positionController,
            readingActivity: readingActivity,
            onError: onError
        )
        navigatorDelegate = delegate
        navigator.delegate = delegate

        let directionalNavigationAdapter = DirectionalNavigationAdapter()
        self.directionalNavigationAdapter = directionalNavigationAdapter
        directionalNavigationAdapter.bind(to: navigator)
    }

    init(
        locationProvider: any ReaderLocationProviding,
        positionController: any ReadingPositionManaging,
        readingActivity: any ReadingActivityManaging = NoopReadingActivityManager(),
        preferencesStore: any ReaderPreferencesStoring = UserDefaultsReaderPreferencesStore(),
        chapters: [ReaderChapter] = [],
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        publication = nil
        self.locationProvider = locationProvider
        readerController = locationProvider as? any EPUBReaderControlling
        self.positionController = positionController
        self.readingActivity = readingActivity
        self.preferencesStore = preferencesStore
        preferences = preferencesStore.load()
        self.chapters = chapters
        contentViewController = locationProvider.viewController
        navigatorDelegate = nil
        directionalNavigationAdapter = nil
        self.onError = onError
    }

    func updatePreferences(_ newValue: ReaderPreferences) throws {
        do {
            var normalized = newValue
            normalized.normalize()
            try preferencesStore.save(normalized)
            preferences = normalized
            readerController?.submitPreferences(normalized.readiumValue)
        } catch {
            onError(error)
            throw error
        }
    }

    func setTapHandler(_ handler: (@MainActor () -> Void)?) {
        navigatorDelegate?.onTap = handler
    }

    @discardableResult
    func go(to chapter: ReaderChapter) async -> Bool {
        await readerController?.go(to: chapter.link, options: .animated) ?? false
    }

    static func restoreInitialLocation(
        bookID: UUID,
        store: any ReaderProgressStore,
        onError: @escaping @MainActor (Error) -> Void
    ) -> RestoredReaderLocation {
        do {
            return try ReaderLocationRestorer.restore(bookID: bookID, from: store)
        } catch {
            onError(error)
            return RestoredReaderLocation(locator: nil, requiresRewrite: false)
        }
    }

    func handleLifecycle(_ state: ReaderLifecycleState) async throws {
        switch state {
        case .active:
            do {
                try await positionController.flush(currentLocator: nil)
                try readingActivity.readerDidBecomeActive()
            } catch {
                onError(error)
                throw error
            }
        case .inactive, .background:
            do {
                let location = locationProvider.currentLocation
                var firstError: Error?
                do { try await positionController.flush(currentLocator: location) } catch { firstError = error }
                do { try await readingActivity.readerBecameInactive() } catch {
                    if firstError == nil { firstError = error }
                }
                if let firstError { throw firstError }
            } catch {
                onError(error)
                throw error
            }
        }
    }

    func close() async throws {
        do {
            let location = locationProvider.currentLocation
            var firstError: Error?
            do { try await positionController.flush(currentLocator: location) } catch { firstError = error }
            do { try await readingActivity.close() } catch {
                if firstError == nil { firstError = error }
            }
            if let firstError { throw firstError }
        } catch {
            onError(error)
            throw error
        }
    }
}

extension EPUBNavigatorViewController: EPUBReaderControlling {
    var viewController: UIViewController { self }
}

@MainActor
private final class ReaderNavigatorDelegate: EPUBNavigatorDelegate {
    private let positionController: ReadingPositionController
    private let readingActivity: any ReadingActivityManaging
    private let onError: @MainActor (Error) -> Void
    private var previousLocation: Locator?
    var onTap: (@MainActor () -> Void)?

    init(
        positionController: ReadingPositionController,
        readingActivity: any ReadingActivityManaging,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.positionController = positionController
        self.readingActivity = readingActivity
        self.onError = onError
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        positionController.record(locator)
        defer { previousLocation = locator }
        guard let previousLocation, previousLocation != locator else { return }
        do {
            try readingActivity.recordReadingInteraction()
        } catch {
            onError(error)
        }
    }

    func navigator(_ navigator: Navigator, didJumpTo locator: Locator) {
        do {
            try readingActivity.recordReadingInteraction()
        } catch {
            onError(error)
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        onError(error)
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        onTap?()
    }
}
