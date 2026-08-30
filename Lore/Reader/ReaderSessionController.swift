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
    private let navigatorDelegate: ReaderNavigatorDelegate?
    private let directionalNavigationAdapter: DirectionalNavigationAdapter?
    private let onError: @MainActor (Error) -> Void

    static func make(
        bookID: UUID,
        fileURL: URL,
        publicationService: ReadiumPublicationService,
        progressStore: any ReaderProgressStore,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) async throws -> ReaderSessionController {
        let opened = try await publicationService.openEPUB(at: fileURL)

        let restoration = restoreInitialLocation(bookID: bookID, store: progressStore, onError: onError)

        let session = try ReaderSessionController(
            bookID: bookID,
            publication: opened.publication,
            initialLocation: restoration.locator,
            progressStore: progressStore,
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

        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation
        )
        locationProvider = navigator
        contentViewController = navigator

        let delegate = ReaderNavigatorDelegate(
            positionController: positionController,
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
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        publication = nil
        self.locationProvider = locationProvider
        self.positionController = positionController
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
            } catch {
                onError(error)
                throw error
            }
        case .inactive, .background:
            do {
                try await positionController.flush(currentLocator: locationProvider.currentLocation)
            } catch {
                onError(error)
                throw error
            }
        }
    }

    func close() async throws {
        do {
            try await positionController.flush(currentLocator: locationProvider.currentLocation)
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
    private let onError: @MainActor (Error) -> Void

    init(
        positionController: ReadingPositionController,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.positionController = positionController
        self.onError = onError
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        positionController.record(locator)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        onError(error)
    }
}
