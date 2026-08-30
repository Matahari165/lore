import Foundation
import ReadiumNavigator
import ReadiumShared

@MainActor
final class ReaderSessionController {
    let publication: Publication
    let navigator: EPUBNavigatorViewController

    private let positionController: ReadingPositionController
    private let navigatorDelegate: ReaderNavigatorDelegate
    private let directionalNavigationAdapter: DirectionalNavigationAdapter
    private let onError: @MainActor (Error) -> Void

    static func make(
        bookID: UUID,
        fileURL: URL,
        publicationService: ReadiumPublicationService,
        progressStore: any ReaderProgressStore,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) async throws -> ReaderSessionController {
        let opened = try await publicationService.openEPUB(at: fileURL)

        let initialLocation: Locator?
        var requiresLocatorRewrite = false
        do {
            if let stored = try progressStore.storedLocator(for: bookID) {
                let decoded = try LocatorPersistenceCodec.decode(stored)
                initialLocation = decoded.locator
                requiresLocatorRewrite = decoded.requiresRewrite
            } else {
                initialLocation = nil
            }
        } catch {
            initialLocation = nil
            onError(error)
        }

        let session = try ReaderSessionController(
            bookID: bookID,
            publication: opened.publication,
            initialLocation: initialLocation,
            progressStore: progressStore,
            onError: onError
        )
        if requiresLocatorRewrite, let initialLocation {
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
        self.navigator = navigator

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

    func handleLifecycle(_ state: ReaderLifecycleState) async throws {
        switch state {
        case .active:
            break
        case .inactive, .background:
            do {
                try await positionController.flush(currentLocator: navigator.currentLocation)
            } catch {
                onError(error)
                throw error
            }
        }
    }

    func close() async throws {
        do {
            try await positionController.flush(currentLocator: navigator.currentLocation)
        } catch {
            onError(error)
            throw error
        }
    }
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
