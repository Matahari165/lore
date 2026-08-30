import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

@MainActor
final class ReaderSessionController {
    let contentViewController: UIViewController

    private let publication: Publication?
    private let locationProvider: any ReaderLocationProviding
    private let positionController: any ReadingPositionManaging
    private let readingActivity: any ReadingActivityManaging
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

        let restoration = restoreInitialLocation(bookID: bookID, store: progressStore, onError: onError)

        let session = try ReaderSessionController(
            bookID: bookID,
            publication: opened.publication,
            initialLocation: restoration.locator,
            progressStore: progressStore,
            readingActivity: readingActivity,
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
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) throws {
        self.publication = publication
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
            initialLocation: initialLocation
        )
        locationProvider = navigator
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
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        publication = nil
        self.locationProvider = locationProvider
        self.positionController = positionController
        self.readingActivity = readingActivity
        contentViewController = locationProvider.viewController
        navigatorDelegate = nil
        directionalNavigationAdapter = nil
        self.onError = onError
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

extension EPUBNavigatorViewController: ReaderLocationProviding {
    var viewController: UIViewController { self }
}

@MainActor
private final class ReaderNavigatorDelegate: EPUBNavigatorDelegate {
    private let positionController: ReadingPositionController
    private let readingActivity: any ReadingActivityManaging
    private let onError: @MainActor (Error) -> Void
    private var previousLocation: Locator?

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
}
