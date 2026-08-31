import Foundation
import ReadiumShared

/// Contexte local correspondant à l'intervalle lu entre deux Locators.
/// Le service IA peut le convertir directement en `PreviousReadingContext`.
struct ReaderAIReadingRecapContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitles: [String]
    let excerpt: String
    let lastReadPositionDescription: String?
}

enum ReadiumReadingRecapContextError: Error, Equatable {
    case invalidInterval
    case contentUnavailable
}

/// Bornage indépendant de Readium, réutilisable dans les tests.
struct ReaderAIReadingRecapWindowing: Sendable {
    static let defaultLimit = 18_000

    static func boundedExcerpt(_ text: String, maximum: Int = defaultLimit) -> String {
        guard maximum > 0 else { return "" }
        guard text.count > maximum else { return text }
        return String(text.suffix(maximum))
    }
}

/// Extrait uniquement ce qui se trouve entre le premier et le dernier Locator
/// d'une journée de lecture.
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
        var pieces: [String] = []
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
            let text = Self.boundedElementText(
                normalizedText,
                locator: element.locator,
                firstLocator: firstElement ? firstLocator : nil,
                lastLocator: sameResourceAsLast ? lastLocator : nil
            )
            if !text.isEmpty { pieces.append(text) }

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

        let excerpt = ReaderAIReadingRecapWindowing.boundedExcerpt(
            pieces.joined(separator: "\n"),
            maximum: maximumCharacters
        )
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

    nonisolated private static func boundedElementText(
        _ text: String,
        locator: Locator,
        firstLocator: Locator?,
        lastLocator: Locator?
    ) -> String {
        var result = text

        if let firstLocator,
           let highlight = Self.normalizedHighlight(firstLocator.text.highlight),
           let range = result.range(of: highlight)
        {
            result = String(result[range.lowerBound...])
        }

        if let lastLocator,
           let highlight = Self.normalizedHighlight(lastLocator.text.highlight),
           let range = result.range(of: highlight)
        {
            result = String(result[..<range.upperBound])
        }

        return result
    }

    nonisolated private static func normalizedHighlight(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = ReaderAIContextWindowing.normalize(value)
        return normalized.isEmpty ? nil : normalized
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
