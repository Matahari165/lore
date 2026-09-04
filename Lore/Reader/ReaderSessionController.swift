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
    private let citationReadingOrder: [Link]
    private let highlightStore: (any HighlightStoring)?
    private let vocabularyStore: (any VocabularyStoring)?
    private let aiService: any LoreAIService
    private let selectionContextExtractor: ReadiumSelectionContextExtractor
    private let recapContextExtractor: ReadiumReadingRecapContextExtractor
    private let recapEngine: DailyReadingRecapEngine?
    private let qualifiedLocatorBox: QualifiedLocatorBox
    private let locationProvider: any ReaderLocationProviding
    private let readerController: (any EPUBReaderControlling)?
    private let positionController: any ReadingPositionManaging
    private let readingActivity: any ReadingActivityManaging
    private let preferencesStore: any ReaderPreferencesStoring
    private let navigatorDelegate: ReaderNavigatorDelegate?
    private let onError: @MainActor (Error) -> Void
    private var highlightChangeHandler: (@MainActor ([ReaderHighlight]) -> Void)?
    private var vocabularyChangeHandler: (@MainActor ([VocabularyItem]) -> Void)?
    private var explanationHandler: (@MainActor (ReaderAIExplanationState) -> Void)?
    private var recapHandler: (@MainActor (ReaderAIRecapState) -> Void)?
    private var explanationTask: Task<Void, Never>?
    private var recapTask: Task<Void, Never>?
    private var navigationHistory: [Locator] = []
    private var navigationHistoryHandler: (@MainActor (Bool) -> Void)?
    private let progressionLocator: @MainActor (Double) async -> Locator?
    private var isNavigating = false
    private(set) var highlights: [ReaderHighlight] = []
    private(set) var vocabulary: [VocabularyItem] = []

    static func make(
        bookID: UUID,
        fileURL: URL,
        publicationService: ReadiumPublicationService,
        progressStore: any ReaderProgressStore,
        readingActivity: any ReadingActivityManaging,
        recapEngine: DailyReadingRecapEngine? = nil,
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
            recapEngine: recapEngine,
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
        recapEngine: DailyReadingRecapEngine? = nil,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) throws {
        self.publication = publication
        self.bookID = bookID
        citationReadingOrder = publication.readingOrder
        highlightStore = progressStore as? any HighlightStoring
        vocabularyStore = progressStore as? any VocabularyStoring
        self.preferences = preferences
        self.preferencesStore = preferencesStore
        self.chapters = chapters
        self.onError = onError
        aiService = OpenAIResponsesClient()
        selectionContextExtractor = ReadiumSelectionContextExtractor()
        recapContextExtractor = ReadiumReadingRecapContextExtractor()
        self.recapEngine = recapEngine
        progressionLocator = { progression in
            await publication.locate(progression: progression)
        }
        let qualifiedLocatorBox = QualifiedLocatorBox(initialLocation)
        self.qualifiedLocatorBox = qualifiedLocatorBox

        let positionController = ReadingPositionController(
            bookID: bookID,
            store: progressStore,
            onError: onError
        )
        self.positionController = positionController
        self.readingActivity = readingActivity

        let highlightAction = EditingAction(title: "Surligner", action: #selector(ReaderContainerViewController.highlightSelection(_:)))
        let vocabularyAction = EditingAction(title: "Vocabulaire", action: #selector(ReaderContainerViewController.addSelectionToVocabulary(_:)))
        let explainAction = EditingAction(title: "Expliquer", action: #selector(ReaderContainerViewController.explainSelection(_:)))
        var cssProperties = CSSRSProperties()
        cssProperties.selectionTextColor = CSSHexColor(ReaderSelectionPalette.text)
        cssProperties.selectionBackgroundColor = CSSHexColor(ReaderSelectionPalette.background)
        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation,
            config: .init(
                preferences: preferences.readiumValue,
                editingActions: [.copy, highlightAction, vocabularyAction, explainAction, .translate, .lookup],
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
            onQualifiedLocation: { [weak recapEngine, weak qualifiedLocatorBox] locator in
                qualifiedLocatorBox?.locator = locator
                guard let recapEngine else { return }
                do {
                    try recapEngine.recordCheckpoint(
                        bookID: bookID,
                        locator: try LocatorPersistenceCodec.encode(locator),
                        at: .now
                    )
                } catch {
                    onError(error)
                }
            },
            onError: onError
        )
        navigatorDelegate = delegate
        navigator.delegate = delegate
        // Première ouverture du jour : le Locator initial (restauration ou position de
        // départ) est enregistré immédiatement, même sans réseau et même sans session
        // active. 100 % local (UserDefaults + SwiftData), aucun appel réseau.
        if let initialLocation, let recapEngine {
            do {
                try recapEngine.recordCheckpoint(
                    bookID: bookID,
                    locator: try LocatorPersistenceCodec.encode(initialLocation),
                    at: .now
                )
            } catch {
                onError(error)
            }
        }
        delegate.onContentStyleRefresh = { [weak self] in
            Task { @MainActor in await self?.reinforceSelectionAppearance() }
        }

        do {
            highlights = try highlightStore?.highlights(for: bookID) ?? []
            applyHighlights(to: navigator)
        } catch {
            onError(error)
        }
        do {
            vocabulary = try vocabularyStore?.allVocabulary() ?? []
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
        progressionLocator: @escaping @MainActor (Double) async -> Locator? = { _ in nil },
        citationBookID: UUID? = nil,
        citationReadingOrder: [Link] = [],
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        publication = nil
        bookID = citationBookID
        self.citationReadingOrder = citationReadingOrder
        highlightStore = nil
        vocabularyStore = nil
        aiService = OpenAIResponsesClient()
        selectionContextExtractor = ReadiumSelectionContextExtractor()
        recapContextExtractor = ReadiumReadingRecapContextExtractor()
        recapEngine = nil
        qualifiedLocatorBox = QualifiedLocatorBox(locationProvider.currentLocation)
        self.locationProvider = locationProvider
        readerController = locationProvider as? any EPUBReaderControlling
        self.positionController = positionController
        self.readingActivity = readingActivity
        self.preferencesStore = preferencesStore
        preferences = preferencesStore.load()
        self.chapters = chapters
        self.progressionLocator = progressionLocator
        contentViewController = locationProvider.viewController
        navigatorDelegate = nil
        self.onError = onError
    }

    func updatePreferences(_ newValue: ReaderPreferences) throws {
        do {
            var normalized = newValue
            normalized.normalize()
            try preferencesStore.save(normalized)
            preferences = normalized
            readerController?.submitPreferences(normalized.readiumValue)
            Task { @MainActor [weak self] in
                await self?.reinforceSelectionAppearance()
            }
        } catch {
            onError(error)
            throw error
        }
    }

    /// Readium applies its CSS variables to every loaded EPUB resource. The
    /// visible WebView gets one additional rule so publisher CSS cannot make
    /// the active selection look like a dark rectangle on a dark page.
    func reinforceSelectionAppearance() async {
        guard let navigator = readerController as? EPUBNavigatorViewController else { return }
        navigator.view.tintColor = ReaderSelectionPalette.handleTint
        _ = await navigator.evaluateJavaScript(
            ReaderSelectionPalette.webViewStyleScript(verticalMargins: preferences.verticalMargins)
        )
    }

    func setTapHandler(_ handler: (@MainActor () -> Void)?) {
        navigatorDelegate?.onChromeTap = handler
    }

    func setHighlightChangeHandler(_ handler: (@MainActor ([ReaderHighlight]) -> Void)?) {
        highlightChangeHandler = handler
        handler?(highlights)
    }

    func setVocabularyChangeHandler(_ handler: (@MainActor ([VocabularyItem]) -> Void)?) {
        vocabularyChangeHandler = handler
        handler?(vocabulary)
    }

    func setExplanationHandler(_ handler: (@MainActor (ReaderAIExplanationState) -> Void)?) {
        explanationHandler = handler
    }

    func setRecapHandler(_ handler: (@MainActor (ReaderAIRecapState) -> Void)?) {
        recapHandler = handler
    }

    func requestDailyRecapIfEligible(at now: Date = .now) {
        guard let recapEngine, let bookID, let publication else { return }
        do {
            guard case let .eligible(window) = try recapEngine.eligibility(for: bookID, at: now) else { return }
            let first = try LocatorPersistenceCodec.decode(window.firstLocator.storedLocator).locator
            let last = try LocatorPersistenceCodec.decode(window.lastLocator.storedLocator).locator
            recapHandler?(.loading)
            recapTask?.cancel()
            recapTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let context = try await recapContextExtractor.extract(
                        from: publication,
                        firstLocator: first,
                        lastLocator: last
                    )
                    let answer = try await aiService.recap(PreviousReadingContext(
                        title: context.title,
                        author: context.author,
                        chapterTitles: context.chapterTitles,
                        excerpt: context.excerpt,
                        lastReadPositionDescription: context.lastReadPositionDescription
                    ))
                    recapHandler?(.answer(answer))
                    try recapEngine.markShown(for: bookID, at: now, completion: .delivered)
                } catch is CancellationError {
                    return
                } catch {
                    recapHandler?(.failure(
                        (error as? LocalizedError)?.errorDescription ?? "Le résumé est indisponible."
                    ))
                    try? recapEngine.markShown(for: bookID, at: now, completion: .failed)
                }
            }
        } catch {
            onError(error)
        }
    }

    func explainCurrentSelection() {
        guard
            let navigator = readerController as? any SelectableNavigator,
            let selection = navigator.currentSelection,
            let publication
        else { return }

        let selectedText = selection.locator.text.highlight?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selectedText.isEmpty else { return }
        explanationHandler?(.loading(selectedText: selectedText))

        explanationTask?.cancel()
        explanationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let extracted = try await selectionContextExtractor.extract(
                    from: publication,
                    selection: selection.locator
                )
                let answer = try await aiService.explain(BookAIContext(
                    title: extracted.title,
                    author: extracted.author,
                    chapterTitle: extracted.sectionTitle,
                    textBefore: extracted.beforeText,
                    selectedText: extracted.selectedText,
                    textAfter: extracted.afterText
                ))
                explanationHandler?(.answer(selectedText: selectedText, text: answer))
            } catch is CancellationError {
                return
            } catch {
                explanationHandler?(.failure(
                    selectedText: selectedText,
                    message: (error as? LocalizedError)?.errorDescription ?? "L’explication est indisponible."
                ))
            }
        }
    }

    func cancelExplanation() {
        explanationTask?.cancel()
        explanationTask = nil
    }

    func cancelDailyRecap() {
        recapTask?.cancel()
        recapTask = nil
    }

    /// Builds the chat context from the position currently known by Readium.
    /// The extractor starts at the first reading-order resource but stops at
    /// the current Locator and remains bounded, so a jump cannot silently
    /// grant the assistant access to unread content.
    func chatContext(
        stage: LoreAIReadingStage,
        question: String,
        history: [LoreAIChatMessage]
    ) async -> LoreAIChatContext? {
        guard let bookID, let publication else { return nil }

        let summaryScope = LoreAISummaryIntentRouter().route(question)
        // Seule une position restaurée ou issue d'une interaction de lecture
        // qualifiée peut ouvrir du contexte. Un simple saut reste insuffisant.
        let currentLocation = qualifiedLocatorBox.locator
        var excerpts: [LoreAIChatExcerpt] = []
        var chapterTitle = currentLocation?.title
        var frontierDescription: String?
        let frontierProgression = currentLocation?.locations.totalProgression

        if stage != .notStarted {
            let requestedInterval: (Locator, Locator, String)? = try? await {
                switch summaryScope {
                case .yesterday:
                    guard let recapEngine,
                          let window = try recapEngine.previousDayWindow(for: bookID, at: .now)
                    else { return nil }
                    return (
                        try LocatorPersistenceCodec.decode(window.firstLocator.storedLocator).locator,
                        try LocatorPersistenceCodec.decode(window.lastLocator.storedLocator).locator,
                        "Portion lue hier"
                    )
                case .currentChapter:
                    guard let currentLocation else { return nil }
                    guard let link = publication.readingOrder.first(where: {
                        $0.url().isEquivalentTo(currentLocation.href)
                    }), let start = await publication.locate(link) else { return nil }
                    return (start, currentLocation, "Chapitre courant déjà lu")
                case .sinceLastSession:
                    // Les sessions enregistrent aujourd'hui leur durée, pas un Locator de départ.
                    // Refuser l'approximation évite d'inclure une autre session ou du texte futur.
                    return nil
                case nil:
                    guard let currentLocation else { return nil }
                    let start: Locator = if let firstLink = publication.readingOrder.first,
                                            let located = await publication.locate(firstLink) {
                        located
                    } else { currentLocation }
                    return (start, currentLocation, "Texte lu jusqu’à la position actuelle")
                }
            }()

            if let requestedInterval, let extracted = try? await recapContextExtractor.extract(
                from: publication,
                firstLocator: requestedInterval.0,
                lastLocator: requestedInterval.1
            ) {
                chapterTitle = requestedInterval.1.title ?? extracted.chapterTitles.last
                frontierDescription = extracted.lastReadPositionDescription
                excerpts = extracted.sourcedExcerpts.enumerated().compactMap { index, excerpt in
                    guard let progression = excerpt.locator.locations.totalProgression,
                          let source = try? Self.chatSource(
                              bookID: bookID,
                              locator: excerpt.locator,
                              label: excerpt.locator.title ?? "Passage \(index + 1)"
                          )
                    else { return nil }
                    return LoreAIChatExcerpt(
                        text: excerpt.text,
                        sourceDescription: excerpt.locator.title ?? requestedInterval.2,
                        progression: progression,
                        source: source
                    )
                }
            }
        }

        let author = publication.metadata.authors.map(\.name).joined(separator: ", ")
        return LoreAIChatContext(
            bookID: bookID,
            title: publication.metadata.title ?? "Livre sans titre",
            author: author.isEmpty ? nil : author,
            stage: stage,
            chapterTitle: chapterTitle,
            readFrontierProgression: frontierProgression,
            readFrontierDescription: frontierDescription,
            excerpts: excerpts,
            // Full-book extraction is intentionally not claimed here. Until a
            // dedicated, user-confirmed extractor is wired, the current
            // Locator remains the only source of text after the end as well.
            fullBookAccessGranted: false,
            summaryScope: summaryScope,
            history: history,
            question: question
        )
    }

    private static func chatSource(bookID: UUID, locator: Locator, label: String) throws -> LoreAIChatSource {
        guard let progression = locator.locations.totalProgression else {
            throw LoreAIError.invalidChatContext
        }
        return LoreAIChatSource(
            id: UUID().uuidString,
            bookID: bookID,
            label: label,
            locatorJSON: try locator.jsonData(),
            locatorSchemaVersion: LocatorPersistenceCodec.currentSchemaVersion,
            progression: progression
        )
    }

    @discardableResult
    func go(to source: LoreAIChatSource) async -> Bool {
        guard source.bookID == bookID,
              source.hasValidIdentityAndProgression,
              source.locatorSchemaVersion == LocatorPersistenceCodec.currentSchemaVersion,
              let decoded = try? LocatorPersistenceCodec.decode(.init(
                  data: source.locatorJSON,
                  schemaVersion: source.locatorSchemaVersion
              )),
              let locatorProgression = decoded.locator.locations.totalProgression,
              source.progression.map({ abs($0 - locatorProgression) <= 0.000_001 }) == true,
              citationReadingOrder.contains(where: { $0.url().isEquivalentTo(decoded.locator.href) }),
              source.progression.map({ $0 <= currentProgression + 0.000_001 }) == true
        else { return false }
        return await readerController?.go(to: decoded.locator, options: .animated) ?? false
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

    func addCurrentSelectionToVocabulary() {
        guard
            let navigator = readerController as? any SelectableNavigator,
            let selection = navigator.currentSelection,
            let text = selection.locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            let bookID,
            let vocabularyStore
        else { return }

        do {
            let item = try vocabularyStore.addVocabulary(
                bookID: bookID,
                locator: selection.locator,
                text: text
            )
            vocabulary.insert(item, at: 0)
            navigator.clearSelection()
            vocabularyChangeHandler?(vocabulary)
        } catch {
            onError(error)
        }
    }

    func deleteVocabularyItem(_ item: VocabularyItem) {
        guard let vocabularyStore else { return }
        do {
            try vocabularyStore.deleteVocabulary(id: item.id, bookID: item.bookID)
            vocabulary.removeAll { $0.id == item.id }
            vocabularyChangeHandler?(vocabulary)
        } catch {
            onError(error)
        }
    }

    @discardableResult
    func go(to vocabularyItem: VocabularyItem) async -> Bool {
        guard vocabularyItem.bookID == bookID else { return false }
        return await navigate(to: vocabularyItem.locator)
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
    func updateNote(_ note: String?, for highlight: ReaderHighlight) -> ReaderHighlight? {
        guard let bookID, let highlightStore else { return nil }
        do {
            let updated = try highlightStore.updateHighlightNote(
                id: highlight.id,
                bookID: bookID,
                note: note
            )
            guard let index = highlights.firstIndex(where: { $0.id == updated.id }) else { return nil }
            highlights[index] = updated
            highlightChangeHandler?(highlights)
            return updated
        } catch {
            onError(error)
            return nil
        }
    }

    @discardableResult
    func go(to highlight: ReaderHighlight) async -> Bool {
        guard highlight.bookID == bookID else { return false }
        return await navigate(to: highlight.locator)
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

    func setNavigationHistoryHandler(_ handler: (@MainActor (Bool) -> Void)?) {
        navigationHistoryHandler = handler
        handler?(!navigationHistory.isEmpty)
    }

    func previewNavigation(at progression: Double) async -> ReaderNavigationPreview {
        let bounded = min(max(progression, 0), 1)
        let locator = await progressionLocator(bounded)
        let title = locator?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = locator.flatMap { locator in
            chapters.first { $0.link.url().isEquivalentTo(locator.href) }?.title
        }
        return ReaderNavigationPreview(
            progression: bounded,
            chapterTitle: title?.isEmpty == false ? title : fallbackTitle,
            isAvailable: locator != nil
        )
    }

    @discardableResult
    func go(toProgression progression: Double) async -> Bool {
        let bounded = min(max(progression, 0), 1)
        guard let destination = await progressionLocator(bounded) else { return false }
        return await navigate(to: destination)
    }

    @discardableResult
    func goBackAfterJump() async -> Bool {
        guard !isNavigating, let destination = navigationHistory.last else { return false }
        isNavigating = true
        defer { isNavigating = false }
        let didNavigate = await readerController?.go(to: destination, options: .animated) ?? false
        guard didNavigate else { return false }
        positionController.record(destination)
        navigationHistory.removeLast()
        navigationHistoryHandler?(!navigationHistory.isEmpty)
        await reinforceSelectionAppearance()
        return true
    }

    var currentProgression: Double {
        locationProvider.currentLocation?.locations.totalProgression ?? 0
    }

    @discardableResult
    func go(to chapter: ReaderChapter) async -> Bool {
        await navigate(to: chapter.link)
    }

    private func navigate(to locator: Locator) async -> Bool {
        guard !isNavigating else { return false }
        let origin = locationProvider.currentLocation
        guard origin != locator else { return true }
        isNavigating = true
        defer { isNavigating = false }
        let didNavigate = await readerController?.go(to: locator, options: .animated) ?? false
        if didNavigate {
            rememberNavigationOrigin(origin)
            positionController.record(locator)
            await reinforceSelectionAppearance()
        }
        return didNavigate
    }

    private func navigate(to link: Link) async -> Bool {
        guard !isNavigating else { return false }
        let origin = locationProvider.currentLocation
        isNavigating = true
        defer { isNavigating = false }
        let didNavigate = await readerController?.go(to: link, options: .animated) ?? false
        if didNavigate {
            rememberNavigationOrigin(origin)
            await reinforceSelectionAppearance()
        }
        return didNavigate
    }

    private func rememberNavigationOrigin(_ locator: Locator?) {
        guard let locator, navigationHistory.last != locator else { return }
        navigationHistory.append(locator)
        navigationHistoryHandler?(true)
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

@MainActor
private final class QualifiedLocatorBox {
    var locator: Locator?

    init(_ locator: Locator?) {
        self.locator = locator
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
    private let onQualifiedLocation: @MainActor (Locator) -> Void
    private var previousLocation: Locator?
    private var selectionActivityPolicy = SelectionActivityPolicy()
    var onChromeTap: (@MainActor () -> Void)?
    var onProgressionChange: (@MainActor (Double) -> Void)?
    var onContentStyleRefresh: (@MainActor () -> Void)?

    init(
        positionController: ReadingPositionController,
        readingActivity: any ReadingActivityManaging,
        onQualifiedLocation: @escaping @MainActor (Locator) -> Void = { _ in },
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.positionController = positionController
        self.readingActivity = readingActivity
        self.onQualifiedLocation = onQualifiedLocation
        self.onError = onError
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        selectionActivityPolicy.reset()
        positionController.record(locator)
        onProgressionChange?(locator.locations.totalProgression ?? 0)
        // Readium may rebuild the same resource after applying preferences.
        // Reapply Lore's final CSS rule after every confirmed location update.
        onContentStyleRefresh?()
        // La première position observée (ouverture sans déplacement) est elle aussi
        // enregistrée : sans cela, une journée avec une seule ouverture sans changement
        // de page n'aurait aucun checkpoint. Enregistrement 100 % local, même hors-ligne.
        // `didJumpTo` (saut par sommaire ou surlignage) ne passe jamais par ici et ne
        // déplace donc ni le premier Locator immuable ni l'intervalle résumé.
        let isFirstObservation = previousLocation == nil
        defer { previousLocation = locator }
        guard isFirstObservation || previousLocation != locator else { return }
        do {
            try readingActivity.recordReadingInteraction()
            if let previousLocation, previousLocation != locator {
                onQualifiedLocation(previousLocation)
            }
            onQualifiedLocation(locator)
        } catch {
            onError(error)
        }
    }

    func navigator(_ navigator: Navigator, didJumpTo locator: Locator) {
        selectionActivityPolicy.reset()
        positionController.record(locator)
        onProgressionChange?(locator.locations.totalProgression ?? 0)
        // Un saut par le sommaire ou vers un surlignage n'est pas une preuve
        // que les chapitres intermédiaires ont été lus.
        previousLocation = locator
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        onError(error)
    }

    func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
        onContentStyleRefresh?()
        if selectionActivityPolicy.shouldRecord(selection.locator) {
            do {
                try readingActivity.recordReadingInteraction()
                onQualifiedLocation(selection.locator)
            } catch {
                onError(error)
            }
        }
        return true
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        onChromeTap?()
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
