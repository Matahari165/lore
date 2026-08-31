import Foundation
import ReadiumShared

/// Texte local transmis au service d'explication après confirmation de l'utilisateur.
///
/// `beforeText` et `afterText` restent dans la même ressource EPUB que la sélection.
/// Ils ne traversent donc jamais silencieusement la frontière d'un chapitre.
struct ReaderAISelectionContext: Equatable, Sendable {
    let title: String
    let author: String?
    let sectionTitle: String?
    let beforeText: String
    let selectedText: String
    let afterText: String
}

enum ReadiumSelectionContextError: Error, Equatable {
    case emptySelection
}

/// Fenêtre textuelle bornée autour d'une sélection.
///
/// Cette logique ne dépend pas de Readium et peut donc être testée avec des
/// chaînes déterministes. Le texte est normalisé pour éviter qu'un EPUB
/// utilisant plusieurs espaces ou retours à la ligne empêche la recherche.
struct ReaderAIContextWindowing: Sendable {
    let beforeText: String
    let selectedText: String
    let afterText: String

    static func make(
        chapterText: String,
        selectedText: String,
        beforeHint: String? = nil,
        beforeLimit: Int = 2_500,
        afterLimit: Int = 2_500,
        totalLimit: Int = 6_000
    ) -> ReaderAIContextWindowing? {
        let selected = normalize(selectedText)
        guard !selected.isEmpty else { return nil }

        let chapter = normalize(chapterText)
        guard !chapter.isEmpty, let range = firstRange(
            of: selected,
            in: chapter,
            matchingBefore: normalize(beforeHint ?? "")
        ) else {
            return ReaderAIContextWindowing(
                beforeText: "",
                selectedText: clip(selected, maximum: min(selected.count, max(totalLimit, 0)), keeping: .start),
                afterText: ""
            )
        }

        let before = String(chapter[..<range.lowerBound])
        let after = String(chapter[range.upperBound...])
        return bounded(before: before, selected: selected, after: after,
                       beforeLimit: beforeLimit, afterLimit: afterLimit, totalLimit: totalLimit)
    }

    private static func firstRange(of selected: String, in chapter: String, matchingBefore hint: String) -> Range<String.Index>? {
        var searchStart = chapter.startIndex
        var firstMatch: Range<String.Index>?
        while searchStart < chapter.endIndex,
              let match = chapter.range(of: selected, range: searchStart ..< chapter.endIndex)
        {
            firstMatch = firstMatch ?? match
            if hint.isEmpty || String(chapter[..<match.lowerBound]).hasSuffix(hint) {
                return match
            }
            searchStart = match.upperBound
        }
        return firstMatch
    }

    /// Recompose une fenêtre lorsque la sélection n'a pas pu être localisée
    /// dans le texte extrait. Le fallback utilise uniquement les informations
    /// déjà contenues dans le Locator.
    static func fallback(
        before: String?,
        selected: String,
        after: String?,
        beforeLimit: Int = 2_500,
        afterLimit: Int = 2_500,
        totalLimit: Int = 6_000
    ) -> ReaderAIContextWindowing? {
        let selected = normalize(selected)
        guard !selected.isEmpty else { return nil }
        return bounded(
            before: normalize(before ?? ""),
            selected: selected,
            after: normalize(after ?? ""),
            beforeLimit: beforeLimit,
            afterLimit: afterLimit,
            totalLimit: totalLimit
        )
    }

    private enum Edge { case start, end }

    private static func bounded(
        before: String,
        selected: String,
        after: String,
        beforeLimit: Int,
        afterLimit: Int,
        totalLimit: Int
    ) -> ReaderAIContextWindowing {
        let safeTotal = max(totalLimit, 0)
        let safeSelection = clip(selected, maximum: safeTotal, keeping: .start)
        let remaining = max(safeTotal - safeSelection.count, 0)

        // On garde les deux côtés, puis on distribue le reliquat au côté qui
        // n'a pas atteint sa limite. Le résultat est toujours <= totalLimit.
        var beforeCount = min(max(beforeLimit, 0), remaining / 2)
        var afterCount = min(max(afterLimit, 0), remaining - beforeCount)
        let unused = remaining - beforeCount - afterCount
        if unused > 0 {
            let beforeExtra = min(unused, max(beforeLimit, 0) - beforeCount)
            beforeCount += beforeExtra
            afterCount += min(unused - beforeExtra, max(afterLimit, 0) - afterCount)
        }

        return ReaderAIContextWindowing(
            beforeText: clip(before, maximum: beforeCount, keeping: .end),
            selectedText: safeSelection,
            afterText: clip(after, maximum: afterCount, keeping: .start)
        )
    }

    private static func clip(_ value: String, maximum: Int, keeping edge: Edge) -> String {
        guard maximum > 0 else { return "" }
        guard value.count > maximum else { return value }
        switch edge {
        case .start:
            return String(value.prefix(maximum))
        case .end:
            return String(value.suffix(maximum))
        }
    }

    static func normalize(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Extrait une fenêtre dans le chapitre courant d'une publication Readium.
///
/// La méthode parcourt uniquement les éléments dont le HREF correspond à la
/// sélection. Elle ne lit donc pas les ressources suivantes de l'EPUB.
@MainActor
final class ReadiumSelectionContextExtractor {
    private let beforeLimit: Int
    private let afterLimit: Int
    private let totalLimit: Int

    init(beforeLimit: Int = 2_500, afterLimit: Int = 2_500, totalLimit: Int = 6_000) {
        self.beforeLimit = beforeLimit
        self.afterLimit = afterLimit
        self.totalLimit = totalLimit
    }

    func extract(from publication: Publication, selection: Locator) async throws -> ReaderAISelectionContext {
        let selected = selection.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty else { throw ReadiumSelectionContextError.emptySelection }

        // Readium's Publication/ContentIterator predate Swift 6 Sendable
        // annotations. Keep their traversal in one explicitly unchecked
        // helper and return only our value-semantic context.
        nonisolated(unsafe) let uncheckedPublication = publication
        return try await Self.extractUnchecked(
            from: uncheckedPublication,
            selection: selection,
            selectedText: selected,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit,
            totalLimit: totalLimit
        )
    }

    nonisolated(unsafe) private static func extractUnchecked(
        from publication: Publication,
        selection: Locator,
        selectedText selected: String,
        beforeLimit: Int,
        afterLimit: Int,
        totalLimit: Int
    ) async throws -> ReaderAISelectionContext {

        let metadataTitle = publication.metadata.title ?? "Livre sans titre"
        let author = publication.metadata.authors.map(\.name).joined(separator: ", ").nilIfEmpty
        let chapterLink = publication.readingOrder.first {
            $0.url().isEquivalentTo(selection.href)
        }
        let chapterTitle = chapterLink?.title

        guard
            let chapterLink,
            let chapterStart = await publication.locate(chapterLink),
            let content = publication.content(from: chapterStart)
        else {
            let fallback = ReaderAIContextWindowing.fallback(
                before: selection.text.before,
                selected: selected,
                after: selection.text.after,
                beforeLimit: beforeLimit,
                afterLimit: afterLimit,
                totalLimit: totalLimit
            )!
            return ReaderAISelectionContext(
                title: metadataTitle,
                author: author,
                sectionTitle: selection.title ?? chapterTitle,
                beforeText: fallback.beforeText,
                selectedText: fallback.selectedText,
                afterText: fallback.afterText
            )
        }

        let iterator = content.iterator()
        var elements: [(text: String, heading: String?)] = []
        while let element = try await iterator.next() {
            guard element.locator.href.isEquivalentTo(selection.href) else { break }
            guard let text = (element as? TextualContentElement)?.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let heading: String? = {
                guard let textElement = element as? TextContentElement else { return nil }
                guard case .heading = textElement.role else { return nil }
                return ReaderAIContextWindowing.normalize(text)
            }()
            elements.append((ReaderAIContextWindowing.normalize(text), heading))
        }

        let chapterText = elements.map(\.text).joined(separator: " ")
        let window = ReaderAIContextWindowing.make(
            chapterText: chapterText,
            selectedText: selected,
            beforeHint: selection.text.before,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit,
            totalLimit: totalLimit
        ) ?? ReaderAIContextWindowing.fallback(
            before: selection.text.before,
            selected: selected,
            after: selection.text.after,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit,
            totalLimit: totalLimit
        )!

        let sectionTitle = selection.title
            ?? Self.headingBefore(selection: selected, in: elements)
            ?? chapterLink.title

        return ReaderAISelectionContext(
            title: metadataTitle,
            author: author,
            sectionTitle: sectionTitle,
            beforeText: window.beforeText,
            selectedText: window.selectedText,
            afterText: window.afterText
        )
    }

    nonisolated private static func headingBefore(selection: String, in elements: [(text: String, heading: String?)]) -> String? {
        let target = ReaderAIContextWindowing.normalize(selection)
        var lastHeading: String?
        for element in elements {
            if element.text.range(of: target) != nil { return lastHeading }
            if let heading = element.heading { lastHeading = heading }
        }
        return lastHeading
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
