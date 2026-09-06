import Foundation
import ReadiumShared

/// Contexte local préparé sans afficher le lecteur.
///
/// Le chargeur ne reçoit jamais l'EPUB en entrée du service IA. Il ouvre le
/// fichier privé, décode le dernier Locator sauvegardé, puis ne conserve que
/// les fragments allant du début demandé jusqu'à cette position.
@MainActor
final class LocalBookAIContextLoader {
    struct Snapshot: Equatable, Sendable {
        let bookID: UUID
        let title: String
        let author: String?
        let stage: LoreAIReadingStage
        let chapterTitle: String?
        let frontierProgression: Double?
        let frontierDescription: String?
        let excerpts: [LoreAIChatExcerpt]
        let fullBookAccessGranted: Bool
        let isAvailable: Bool
        let unavailableMessage: String?

        init(
            bookID: UUID,
            title: String,
            author: String?,
            stage: LoreAIReadingStage,
            chapterTitle: String?,
            frontierProgression: Double?,
            frontierDescription: String?,
            excerpts: [LoreAIChatExcerpt],
            fullBookAccessGranted: Bool = false,
            isAvailable: Bool,
            unavailableMessage: String?
        ) {
            self.bookID = bookID
            self.title = title
            self.author = author
            self.stage = stage
            self.chapterTitle = chapterTitle
            self.frontierProgression = frontierProgression
            self.frontierDescription = frontierDescription
            self.excerpts = excerpts
            self.fullBookAccessGranted = fullBookAccessGranted
            self.isAvailable = isAvailable
            self.unavailableMessage = unavailableMessage
        }

        func chatContext(
            summaryScope: LoreAISummaryScope?,
            question: String,
            history: [LoreAIChatMessage]
        ) -> LoreAIChatContext {
            LoreAIChatContext(
                bookID: bookID,
                title: title,
                author: author,
                stage: stage,
                chapterTitle: chapterTitle,
                readFrontierProgression: frontierProgression,
                readFrontierDescription: frontierDescription,
                excerpts: isAvailable ? excerpts : [],
                fullBookAccessGranted: fullBookAccessGranted,
                summaryScope: summaryScope,
                history: history,
                question: question
            )
        }
    }

    private struct BookInput: Sendable {
        let id: UUID
        let title: String
        let author: String?
        let stage: LoreAIReadingStage
        let relativeFilePath: String
        let lastLocatorJSON: Data?
        let locatorSchemaVersion: Int?
        let lastProgression: Double?
    }

    private let book: BookInput
    private let fileStore: BookFileStore
    private let publicationService: ReadiumPublicationService
    private let extractor: ReadiumReadingRecapContextExtractor
    private var cachedSnapshots: [String: Snapshot] = [:]

    init(
        book: BookRecord,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService = ReadiumPublicationService(),
        extractor: ReadiumReadingRecapContextExtractor = ReadiumReadingRecapContextExtractor()
    ) {
        self.book = BookInput(
            id: book.id,
            title: book.title,
            author: book.author,
            stage: book.readingStatus.loreAIStage,
            relativeFilePath: book.relativeFilePath,
            lastLocatorJSON: book.lastLocatorJSON,
            locatorSchemaVersion: book.locatorSchemaVersion,
            lastProgression: book.lastProgression
        )
        self.fileStore = fileStore
        self.publicationService = publicationService
        self.extractor = extractor
    }

    /// Default construction is intentionally local and private: no account,
    /// key, network call or remote book source is involved.
    static func makeDefault(book: BookRecord) -> LocalBookAIContextLoader? {
        guard let fileStore = try? BookFileStore() else { return nil }
        return LocalBookAIContextLoader(book: book, fileStore: fileStore)
    }

    func snapshot(for scope: LoreAISummaryScope?) async throws -> Snapshot {
        let cacheKey = scope?.rawValue ?? "read-so-far"
        if let cached = cachedSnapshots[cacheKey] {
            return cached
        }

        let snapshot: Snapshot
        if book.stage == .notStarted {
            snapshot = Snapshot(
                bookID: book.id,
                title: book.title,
                author: book.author,
                stage: book.stage,
                chapterTitle: nil,
                frontierProgression: nil,
                frontierDescription: nil,
                excerpts: [],
                isAvailable: true,
                unavailableMessage: nil
            )
        } else if scope == .yesterday || scope == .sinceLastSession {
            snapshot = unavailableSnapshot(
                "Les bornes locales de cette période ne sont pas disponibles depuis la fiche du livre."
            )
        } else {
            snapshot = try await extract(scope: scope)
        }

        cachedSnapshots[cacheKey] = snapshot
        return snapshot
    }

    private func extract(scope: LoreAISummaryScope?) async throws -> Snapshot {
        guard !book.relativeFilePath.isEmpty else {
            throw LocalBookAIContextLoaderError.fileUnavailable
        }

        let fullBookAccessGranted = book.stage == .finished && scope == nil
        let current: Locator?
        if fullBookAccessGranted {
            current = nil
        } else if let lastLocatorJSON = book.lastLocatorJSON {
            current = try LocatorPersistenceCodec.decode(.init(
                data: lastLocatorJSON,
                schemaVersion: book.locatorSchemaVersion
            )).locator
        } else {
            return unavailableSnapshot("Aucune position de lecture sauvegardée n’est disponible.")
        }

        let currentProgression = current?.locations.totalProgression
        if !fullBookAccessGranted,
           let lastProgression = book.lastProgression,
           let currentProgression,
           abs(lastProgression - currentProgression) > 0.000_001
        {
            throw LocalBookAIContextLoaderError.inconsistentSavedProgress
        }

        let fileURL = try fileStore.fileURL(for: book.relativeFilePath)
        let opened = try await publicationService.openEPUB(at: fileURL)
        nonisolated(unsafe) let publication = opened.publication

        let recap: ReaderAIReadingRecapContext
        let description: String
        if fullBookAccessGranted {
            recap = try await extractor.extractEntireBook(from: publication)
            description = "Livre entier autorisé après la fin de lecture"
        } else {
            guard let current else {
                throw LocalBookAIContextLoaderError.chapterUnavailable
            }
            let firstLocator: Locator
            switch scope {
            case .currentChapter:
                guard let link = publication.readingOrder.first(where: {
                    $0.url().isEquivalentTo(current.href)
                }), let located = await publication.locate(link) else {
                    throw LocalBookAIContextLoaderError.chapterUnavailable
                }
                firstLocator = located
                description = "Chapitre lu jusqu’à la position sauvegardée"
            case nil:
                guard let link = publication.readingOrder.first,
                      let located = await publication.locate(link)
                else {
                    throw LocalBookAIContextLoaderError.readingOrderUnavailable
                }
                firstLocator = located
                description = "Texte lu jusqu’à la position sauvegardée"
            case .yesterday, .sinceLastSession:
                throw LocalBookAIContextLoaderError.intervalUnavailable
            }

            recap = try await extractor.extract(
                from: publication,
                firstLocator: firstLocator,
                lastLocator: current
            )
        }
        let excerpts = recap.sourcedExcerpts.enumerated().compactMap { index, excerpt -> LoreAIChatExcerpt? in
            guard let progression = excerpt.locator.locations.totalProgression,
                  let locatorJSON = try? excerpt.locator.jsonData()
            else { return nil }
            let source = LoreAIChatSource(
                id: "local-\(book.id.uuidString)-\(index)-\(progression)",
                bookID: book.id,
                label: excerpt.locator.title ?? "Passage \(index + 1)",
                locatorJSON: locatorJSON,
                locatorSchemaVersion: LocatorPersistenceCodec.currentSchemaVersion,
                progression: progression
            )
            return LoreAIChatExcerpt(
                text: excerpt.text,
                sourceDescription: excerpt.locator.title ?? description,
                progression: progression,
                source: source
            )
        }

        guard !excerpts.isEmpty else {
            return unavailableSnapshot("Le texte correspondant à la position sauvegardée n’a pas pu être extrait.")
        }

        return Snapshot(
            bookID: book.id,
            title: opened.title ?? book.title,
            author: opened.author ?? book.author,
            stage: book.stage,
            chapterTitle: recap.chapterTitles.last,
            frontierProgression: fullBookAccessGranted ? nil : (currentProgression ?? book.lastProgression),
            frontierDescription: fullBookAccessGranted
                ? description
                : (recap.lastReadPositionDescription ?? description),
            excerpts: excerpts,
            fullBookAccessGranted: fullBookAccessGranted,
            isAvailable: true,
            unavailableMessage: nil
        )
    }

    private func unavailableSnapshot(_ message: String) -> Snapshot {
        Snapshot(
            bookID: book.id,
            title: book.title,
            author: book.author,
            stage: book.stage,
            chapterTitle: nil,
            frontierProgression: book.lastProgression,
            frontierDescription: book.lastProgression.map {
                "Progression sauvegardée : \($0.formatted(.percent.precision(.fractionLength(0))))"
            },
            excerpts: [],
            isAvailable: false,
            unavailableMessage: message
        )
    }
}

enum LocalBookAIContextLoaderError: LocalizedError, Equatable {
    case fileUnavailable
    case inconsistentSavedProgress
    case chapterUnavailable
    case readingOrderUnavailable
    case intervalUnavailable

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:
            "Le fichier EPUB privé de ce livre est introuvable."
        case .inconsistentSavedProgress:
            "La position sauvegardée est incohérente ; aucun texte n’a été envoyé."
        case .chapterUnavailable:
            "Le chapitre correspondant à la position sauvegardée est introuvable."
        case .readingOrderUnavailable:
            "L’ordre de lecture de ce livre est indisponible."
        case .intervalUnavailable:
            "L’intervalle local demandé n’est pas disponible."
        }
    }
}
