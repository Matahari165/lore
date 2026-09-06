import Foundation
import ReadiumShared

/// Contexte local correspondant à l'intervalle lu entre deux Locators.
/// Le service IA peut le convertir directement en `PreviousReadingContext`.
struct ReaderAIReadingRecapContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitles: [String]
    let excerpt: String
    let sourcedExcerpts: [ReaderAISourcedExcerpt]
    let lastReadPositionDescription: String?
}

struct ReaderAISourcedExcerpt: Equatable, Sendable {
    let text: String
    let locator: Locator
}

enum ReadiumReadingRecapContextError: Error, Equatable {
    case invalidInterval
    case contentUnavailable
}

/// Bornage indépendant de Readium, réutilisable dans les tests.
/// Politique de troncature : seul le suffixe (le texte le plus récent) est conservé.
/// Au-delà de la limite validée (18 000 caractères), les pages intermédiaires les plus
/// anciennes sont donc résumées par la fin, pas par le début ni par échantillonnage.
/// Ne pas élargir cette limite sans validation (coût, latence, énergie).
struct ReaderAIReadingRecapWindowing: Sendable {
    static let defaultLimit = 18_000

    static func boundedExcerpt(_ text: String, maximum: Int = defaultLimit) -> String {
        guard maximum > 0 else { return "" }
        guard text.count > maximum else { return text }
        return String(text.suffix(maximum))
    }
}

/// Extrait uniquement ce qui se trouve entre le premier et le dernier Locator
/// d'une journée de lecture, bornes incluses.
/// L'itération démarre au premier Locator (`publication.content(from:)`) et traverse
/// TOUTES les ressources intermédiaires de l'ordre de lecture ; seul l'élément
/// contenant le dernier Locator arrête la traversée. Le premier Locator est immuable
/// et le dernier est mobile (`DailyReadingRecapEngine.recordCheckpoint`), donc un saut
/// (`didJumpTo`, qui n'enregistre jamais de checkpoint) ne fausse pas l'intervalle :
/// l'extrait couvre toujours l'intégralité first…last.
@MainActor
final class ReadiumReadingRecapContextExtractor {
    private let maximumCharacters: Int

    init(maximumCharacters: Int = ReaderAIReadingRecapWindowing.defaultLimit) {
        self.maximumCharacters = maximumCharacters
    }

    func extract(
        from publication: Publication,
        firstLocator: Locator,
        lastLocator: Locator
    ) async throws -> ReaderAIReadingRecapContext {
        nonisolated(unsafe) let uncheckedPublication = publication
        return try await Self.extractUnchecked(
            from: uncheckedPublication,
            firstLocator: firstLocator,
            lastLocator: lastLocator,
            maximumCharacters: maximumCharacters
        )
    }

    /// Extrait des passages couvrant le livre entier pour une discussion
    /// explicitement autorisée après la fin de lecture. Le texte reste borné
    /// avant l'envoi ; le fichier EPUB complet reste toujours sur l'appareil.
    func extractEntireBook(from publication: Publication) async throws -> ReaderAIReadingRecapContext {
        nonisolated(unsafe) let uncheckedPublication = publication
        return try await Self.extractEntireBookUnchecked(
            from: uncheckedPublication,
            maximumCharacters: maximumCharacters
        )
    }

    nonisolated private static func extractEntireBookUnchecked(
        from publication: Publication,
        maximumCharacters: Int
    ) async throws -> ReaderAIReadingRecapContext {
        let title = publication.metadata.title ?? "Livre sans titre"
        let author = publication.metadata.authors.map(\.name).joined(separator: ", ").nilIfEmpty
        var pieces: [ReaderAISourcedExcerpt] = []
        var chapters: [String] = []
        var firstLocator: Locator?
        var lastLocator: Locator?

        guard let content = publication.content() else {
            throw ReadiumReadingRecapContextError.contentUnavailable
        }

        let iterator = content.iterator()
        while let element = try await iterator.next() {
            guard let rawText = (element as? TextualContentElement)?.text,
                  !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            if firstLocator == nil { firstLocator = element.locator }
            lastLocator = element.locator

            let normalizedText = ReaderAIContextWindowing.normalize(rawText)
            if let textElement = element as? TextContentElement,
               case .heading = textElement.role,
               !normalizedText.isEmpty,
               !chapters.contains(normalizedText)
            {
                chapters.append(normalizedText)
            }
            if let locatorTitle = element.locator.title,
               !locatorTitle.isEmpty,
               !chapters.contains(locatorTitle)
            {
                chapters.append(locatorTitle)
            }

            if let piece = boundedElement(
                rawText,
                locator: element.locator,
                firstLocator: nil,
                lastLocator: nil
            ) {
                pieces.append(piece)
            }
        }

        // Keep a representative sample of the beginning, middle and end rather
        // than sending only the final pages of a finished book. The prompt has
        // a 12,000-character budget, so this limit keeps the whole selected
        // sample available to the prompt builder without a second truncation.
        let sourcedExcerpts = representativePieces(
            pieces,
            maximum: min(maximumCharacters, 12_000)
        )
        let excerpt = sourcedExcerpts.map(\.text).joined(separator: "\n")
        guard !excerpt.isEmpty, let firstLocator, let lastLocator else {
            throw ReadiumReadingRecapContextError.contentUnavailable
        }

        return ReaderAIReadingRecapContext(
            title: title,
            author: author,
            chapterTitles: chapters.isEmpty
                ? Array(ofNotNil: firstLocator.title ?? lastLocator.title)
                : chapters,
            excerpt: excerpt,
            sourcedExcerpts: sourcedExcerpts,
            lastReadPositionDescription: "Livre terminé"
        )
    }

    nonisolated private static func extractUnchecked(
        from publication: Publication,
        firstLocator: Locator,
        lastLocator: Locator,
        maximumCharacters: Int
    ) async throws -> ReaderAIReadingRecapContext {
        guard
            publication.readingOrder.contains(where: { $0.url().isEquivalentTo(firstLocator.href) }),
            publication.readingOrder.contains(where: { $0.url().isEquivalentTo(lastLocator.href) })
        else {
            throw ReadiumReadingRecapContextError.invalidInterval
        }

        guard let content = publication.content(from: firstLocator) else {
            throw ReadiumReadingRecapContextError.contentUnavailable
        }

        let title = publication.metadata.title ?? "Livre sans titre"
        let author = publication.metadata.authors.map(\.name).joined(separator: ", ").nilIfEmpty
        let iterator = content.iterator()
        var pieces: [ReaderAISourcedExcerpt] = []
        var chapters: [String] = []
        var reachedLast = false
        var firstElement = true

        while let element = try await iterator.next() {
            let elementHref = element.locator.href
            let sameResourceAsLast = elementHref.isEquivalentTo(lastLocator.href)

            // Intermediate resources are part of the interval. Only the
            // element containing the final Locator ends the traversal.
            if sameResourceAsLast && Self.shouldStopBefore(element.locator, target: lastLocator) {
                reachedLast = true
                break
            }

            guard let rawText = (element as? TextualContentElement)?.text,
                  !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                if sameResourceAsLast && Self.isAtOrAfter(element.locator, target: lastLocator) {
                    reachedLast = true
                    break
                }
                continue
            }

            let normalizedText = ReaderAIContextWindowing.normalize(rawText)
            let piece: ReaderAISourcedExcerpt?
            if sameResourceAsLast && Self.isStrictlyBefore(element.locator, target: lastLocator) {
                // A progression-only frontier cannot safely clip the current
                // element, but complete elements strictly before it are safe.
                piece = Self.boundedElement(
                    rawText,
                    locator: element.locator,
                    firstLocator: firstElement ? firstLocator : nil,
                    lastLocator: nil
                )
            } else {
                piece = Self.boundedElement(
                    rawText,
                    locator: element.locator,
                    firstLocator: firstElement ? firstLocator : nil,
                    lastLocator: sameResourceAsLast ? lastLocator : nil
                )
            }
            if let piece { pieces.append(piece) }

            if let textElement = element as? TextContentElement,
               case .heading = textElement.role,
               !normalizedText.isEmpty,
               !chapters.contains(normalizedText)
            {
                chapters.append(normalizedText)
            }
            if let locatorTitle = element.locator.title,
               !locatorTitle.isEmpty,
               !chapters.contains(locatorTitle)
            {
                chapters.append(locatorTitle)
            }

            firstElement = false

            if sameResourceAsLast && Self.isAtOrAfter(element.locator, target: lastLocator) {
                reachedLast = true
                break
            }
        }

        guard reachedLast else {
            throw ReadiumReadingRecapContextError.invalidInterval
        }

        let sourcedExcerpts = Self.boundedPieces(pieces, maximum: maximumCharacters)
        let excerpt = sourcedExcerpts.map(\.text).joined(separator: "\n")
        guard !excerpt.isEmpty else {
            throw ReadiumReadingRecapContextError.contentUnavailable
        }

        let chapterTitles = chapters.isEmpty
            ? Array(ofNotNil: firstLocator.title ?? lastLocator.title)
            : chapters

        return ReaderAIReadingRecapContext(
            title: title,
            author: author,
            chapterTitles: chapterTitles,
            excerpt: excerpt,
            sourcedExcerpts: sourcedExcerpts,
            lastReadPositionDescription: lastLocator.title
        )
    }

    nonisolated private static func isAtOrAfter(_ locator: Locator, target: Locator) -> Bool {
        guard locator.href.isEquivalentTo(target.href) else { return false }

        if let targetSelector = target.locations["cssSelector"]?.string {
            return locator.locations["cssSelector"]?.string == targetSelector
        }
        if let targetProgression = target.locations.progression,
           let progression = locator.locations.progression
        {
            return progression >= targetProgression
        }
        if let targetPosition = target.locations.position,
           let position = locator.locations.position
        {
            return position >= targetPosition
        }

        // Sans expression de position, s'arrêter au premier élément de la
        // ressource est le comportement prudent : aucun texte futur n'est lu.
        return true
    }

    nonisolated private static func shouldStopBefore(_ locator: Locator, target: Locator) -> Bool {
        guard locator.href.isEquivalentTo(target.href) else { return false }
        guard target.locations["cssSelector"]?.string == nil else { return false }

        if let targetProgression = target.locations.progression,
           let progression = locator.locations.progression
        {
            return progression > targetProgression
        }
        if let targetPosition = target.locations.position,
           let position = locator.locations.position
        {
            return position > targetPosition
        }
        return false
    }

    nonisolated private static func isStrictlyBefore(_ locator: Locator, target: Locator) -> Bool {
        guard locator.href.isEquivalentTo(target.href) else { return false }
        if let targetProgression = target.locations.progression,
           let progression = locator.locations.progression
        {
            return progression < targetProgression
        }
        if let targetPosition = target.locations.position,
           let position = locator.locations.position
        {
            return position < targetPosition
        }
        return false
    }

    nonisolated static func boundedElement(
        _ text: String,
        locator: Locator,
        firstLocator: Locator?,
        lastLocator: Locator?
    ) -> ReaderAISourcedExcerpt? {
        // Readium may normalize `TextContentElement.text` while keeping the
        // Locator highlight in its original DOM representation. The Locator
        // text is the only safe coordinate space for a clickable citation.
        guard let locatorText = rawHighlight(locator.text.highlight),
              ReaderAIContextWindowing.normalize(locatorText) == ReaderAIContextWindowing.normalize(text)
        else { return nil }
        var range = locatorText.startIndex..<locatorText.endIndex

        if let firstLocator,
           let highlight = Self.rawHighlight(firstLocator.text.highlight),
           let found = locatorText.range(of: highlight)
        {
            range = found.lowerBound..<range.upperBound
        }

        if let lastLocator {
            // A progression or a selector identifies at best an element, not
            // an exact character boundary. Including that whole element could
            // leak text located after the user's real frontier.
            guard let highlight = Self.rawHighlight(lastLocator.text.highlight),
                  let found = locatorText.range(of: highlight)
            else { return nil }
            range = range.lowerBound..<found.upperBound
        }

        guard range.lowerBound < range.upperBound else { return nil }
        let clipped = String(locatorText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return nil }
        guard let locatorRange = locatorText.range(of: clipped, range: range) else { return nil }
        let exactLocator = locator.copy(text: { $0 = $0[locatorRange] })
        return ReaderAISourcedExcerpt(text: clipped, locator: exactLocator)
    }

    nonisolated static func boundedPieces(
        _ pieces: [ReaderAISourcedExcerpt],
        maximum: Int
    ) -> [ReaderAISourcedExcerpt] {
        guard maximum > 0 else { return [] }
        var remaining = maximum
        var result: [ReaderAISourcedExcerpt] = []
        for piece in pieces.reversed() where remaining > 0 {
            if piece.text.count <= remaining {
                result.append(piece)
                remaining -= piece.text.count
            } else {
                let range = piece.text.index(piece.text.endIndex, offsetBy: -remaining)..<piece.text.endIndex
                let clipped = String(piece.text[range])
                guard let locatorHighlight = piece.locator.text.highlight,
                      let locatorRange = locatorHighlight.range(of: clipped, options: .backwards)
                else { continue }
                let locator = piece.locator.copy(text: { $0 = $0[locatorRange] })
                result.append(.init(text: clipped, locator: locator))
                remaining = 0
            }
        }
        return result.reversed()
    }

    /// Selects bounded excerpts distributed across an entire finished book.
    /// Each returned Locator remains aligned with its clipped text.
    nonisolated static func representativePieces(
        _ pieces: [ReaderAISourcedExcerpt],
        maximum: Int
    ) -> [ReaderAISourcedExcerpt] {
        guard maximum > 0, !pieces.isEmpty else { return [] }
        let total = pieces.reduce(0) { $0 + $1.text.count }
        guard total > maximum else { return pieces }

        let slotCount = min(pieces.count, max(3, maximum / 600))
        let perSlot = max(1, maximum / slotCount)
        var indices: [Int] = []
        var seen = Set<Int>()
        for slot in 0..<slotCount {
            let index = slotCount == 1
                ? 0
                : Int((Double(slot) * Double(pieces.count - 1)) / Double(slotCount - 1))
            if seen.insert(index).inserted { indices.append(index) }
        }

        return indices.flatMap { index in
            boundedPieces([pieces[index]], maximum: perSlot)
        }
    }

    nonisolated private static func rawHighlight(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
