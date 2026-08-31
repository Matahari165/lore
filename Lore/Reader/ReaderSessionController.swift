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
    private let bookID: UUID?
    private let highlightStore: (any HighlightStoring)?
    private let locationProvider: any ReaderLocationProviding
    private let readerController: (any EPUBReaderControlling)?
    private let positionController: any ReadingPositionManaging
    private let readingActivity: any ReadingActivityManaging
    private let preferencesStore: any ReaderPreferencesStoring
    private let navigatorDelegate: ReaderNavigatorDelegate?
    private let directionalNavigationAdapter: DirectionalNavigationAdapter?
    private let onError: @MainActor (Error) -> Void
    private var highlightChangeHandler: (@MainActor ([ReaderHighlight]) -> Void)?
    private(set) var highlights: [ReaderHighlight] = []

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
        self.bookID = bookID
        highlightStore = progressStore as? any HighlightStoring
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

        let highlightAction = EditingAction(title: "Surligner", action: #selector(ReaderContainerViewController.highlightSelection(_:)))
        var cssProperties = CSSRSProperties()
        cssProperties.selectionTextColor = CSSHexColor("#111111")
        cssProperties.selectionBackgroundColor = CSSHexColor("#FFD54F")
        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation,
            config: .init(
                preferences: preferences.readiumValue,
                editingActions: [.copy, .translate, .lookup, highlightAction],
                disablePageTurnsWhileScrolling: true,
                readiumCSSRSProperties: cssProperties
            )
        )
        locationProvider = navigator
        readerController = navigator
        contentViewController = navigator

        let delegate = ReaderNavigatorDelegate(
            positionController: positionController,
            readingActivity: readingActivity,
            isRTL: publication.metadata.readingProgression == .rtl,
            onError: onError
        )
        navigatorDelegate = delegate
        navigator.delegate = delegate

        let directionalNavigationAdapter = DirectionalNavigationAdapter(
            pointerPolicy: .init(
                edges: .horizontal,
                ignoreWhileScrolling: true,
                horizontalEdgeThresholdPercent: 1 / 3
            ),
            animatedTransition: true
        )
        self.directionalNavigationAdapter = directionalNavigationAdapter
        directionalNavigationAdapter.bind(to: navigator)

        do {
            highlights = try highlightStore?.highlights(for: bookID) ?? []
            applyHighlights(to: navigator)
        } catch {
            onError(error)
        }
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
        bookID = nil
        highlightStore = nil
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
        navigatorDelegate?.onChromeTap = handler
    }

    func setHighlightChangeHandler(_ handler: (@MainActor ([ReaderHighlight]) -> Void)?) {
        highlightChangeHandler = handler
        handler?(highlights)
    }

    func highlightCurrentSelection() {
        guard
            let navigator = readerController as? (any SelectableNavigator & DecorableNavigator),
            let selection = navigator.currentSelection,
            let text = selection.locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let bookID,
            let highlightStore
        else { return }

        do {
            let highlight = try highlightStore.addHighlight(
                bookID: bookID,
                locator: selection.locator,
                text: text,
                color: .yellow
            )
            highlights.insert(highlight, at: 0)
            applyHighlights(to: navigator)
            navigator.clearSelection()
            highlightChangeHandler?(highlights)
        } catch {
            onError(error)
        }
    }

    func deleteHighlight(_ highlight: ReaderHighlight) {
        guard let bookID, let highlightStore else { return }
        do {
            try highlightStore.deleteHighlight(id: highlight.id, bookID: bookID)
            highlights.removeAll { $0.id == highlight.id }
            if let navigator = readerController as? any DecorableNavigator { applyHighlights(to: navigator) }
            highlightChangeHandler?(highlights)
        } catch {
            onError(error)
        }
    }

    @discardableResult
    func go(to highlight: ReaderHighlight) async -> Bool {
        await readerController?.go(to: highlight.locator, options: .animated) ?? false
    }

    private func applyHighlights(to navigator: any DecorableNavigator) {
        guard navigator.supports(decorationStyle: .highlight) else { return }
        navigator.apply(
            decorations: highlights.map {
                Decoration(id: $0.id.uuidString, locator: $0.locator, style: .highlight(tint: $0.color.uiColor))
            },
            in: "lore-highlights"
        )
    }

    func setProgressionHandler(_ handler: (@MainActor (Double) -> Void)?) {
        navigatorDelegate?.onProgressionChange = handler
        handler?(currentProgression)
    }

    var currentProgression: Double {
        locationProvider.currentLocation?.locations.totalProgression ?? 0
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
    private var selectionActivityPolicy = SelectionActivityPolicy()
    private let isRTL: Bool
    var onChromeTap: (@MainActor () -> Void)?
    var onProgressionChange: (@MainActor (Double) -> Void)?

    init(
        positionController: ReadingPositionController,
        readingActivity: any ReadingActivityManaging,
        isRTL: Bool,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.positionController = positionController
        self.readingActivity = readingActivity
        self.isRTL = isRTL
        self.onError = onError
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        selectionActivityPolicy.reset()
        positionController.record(locator)
        onProgressionChange?(locator.locations.totalProgression ?? 0)
        defer { previousLocation = locator }
        guard let previousLocation, previousLocation != locator else { return }
        do {
            try readingActivity.recordReadingInteraction()
        } catch {
            onError(error)
        }
    }

    func navigator(_ navigator: Navigator, didJumpTo locator: Locator) {
        selectionActivityPolicy.reset()
        onProgressionChange?(locator.locations.totalProgression ?? 0)
        do {
            try readingActivity.recordReadingInteraction()
        } catch {
            onError(error)
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        onError(error)
    }

    func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
        if selectionActivityPolicy.shouldRecord(selection.locator) {
            do {
                try readingActivity.recordReadingInteraction()
            } catch {
                onError(error)
            }
        }
        return true
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        if ReaderTapZone.resolve(x: point.x, width: navigator.view.bounds.width, isRTL: isRTL) == .chrome {
            onChromeTap?()
        }
    }
}

struct SelectionActivityPolicy {
    private var lastLocatorData: Data?

    mutating func shouldRecord(_ locator: Locator) -> Bool {
        guard
            let text = locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let data = try? locator.jsonData(),
            data != lastLocatorData
        else { return false }
        lastLocatorData = data
        return true
    }

    mutating func reset() {
        lastLocatorData = nil
    }
}
