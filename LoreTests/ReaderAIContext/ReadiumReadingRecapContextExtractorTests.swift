import Foundation
import ReadiumShared
import Testing
@testable import Lore

struct ReadiumReadingRecapContextExtractorTests {
    @Test func recapExcerptIsBoundedToTheNewestReadText() {
        let text = "début" + String(repeating: " lu", count: 8) + " fin"

        let excerpt = ReaderAIReadingRecapWindowing.boundedExcerpt(text, maximum: 20)

        #expect(excerpt.count == 20)
        #expect(excerpt == String(text.suffix(20)))
        #expect(!excerpt.contains("début"))
    }

    @Test func recapWindowPreservesShortIntervalsExactly() {
        #expect(ReaderAIReadingRecapWindowing.boundedExcerpt("hier lu") == "hier lu")
        #expect(ReaderAIReadingRecapWindowing.boundedExcerpt("texte", maximum: 0).isEmpty)
    }

    @Test func recapBeyondTheValidatedLimitKeepsOnlyTheMostRecentText() {
        // Politique documentée : au-delà de 18 000 caractères validés, seules les pages
        // les plus récentes (suffixe) alimentent le résumé. Ne pas élargir sans validation.
        #expect(ReaderAIReadingRecapWindowing.defaultLimit == 18_000)
        let text = String(repeating: "a", count: 19_000) + "FIN"

        let excerpt = ReaderAIReadingRecapWindowing.boundedExcerpt(text)

        #expect(excerpt.count == 18_000)
        #expect(excerpt.hasSuffix("FIN"))
        #expect(excerpt == String(text.suffix(18_000)))
    }

    @Test func exactSlicePreservesRawWhitespaceAndRecalculatesLocatorText() throws {
        let raw = "Avant  deux espaces\nPassage exact\nSuite interdite"
        let element = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(totalProgression: 0.4),
            text: .init(after: "Après", before: "Contexte", highlight: "\n\(raw)  ")
        )
        let frontier = element.copy(text: { locatorText in
            let highlight = locatorText.highlight!
            locatorText = locatorText[highlight.range(of: "Passage exact")!]
        })
        let piece = try #require(ReadiumReadingRecapContextExtractor.boundedElement(
            raw, locator: element, firstLocator: nil, lastLocator: frontier
        ))

        #expect(piece.text == "Avant  deux espaces\nPassage exact")
        #expect(piece.locator.text.highlight == piece.text)
        #expect(piece.locator.text.after?.contains("Suite interdite") == true)
        #expect(!piece.text.contains("Suite interdite"))
    }

    @Test func normalizedReadiumTextUsesOnlyLocatorCoordinateSpace() throws {
        let raw = "Avant  deux espaces\nPassage exact"
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(totalProgression: 0.4),
            text: .init(highlight: "Avant deux espaces Passage exact")
        )

        let piece = try #require(ReadiumReadingRecapContextExtractor.boundedElement(
            raw, locator: locator, firstLocator: nil, lastLocator: nil
        ))
        #expect(piece.text == "Avant deux espaces Passage exact")
        #expect(piece.locator.text.highlight == piece.text)
    }

    @Test func frontierWithoutRawHighlightRefusesWholeElement() {
        let raw = "Début lu. Suite non lue."
        let element = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(progression: 0.5, totalProgression: 0.5),
            text: .init(highlight: raw)
        )
        let progressionOnly = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(progression: 0.5, totalProgression: 0.5)
        )
        #expect(ReadiumReadingRecapContextExtractor.boundedElement(
            raw, locator: element, firstLocator: nil, lastLocator: progressionOnly
        ) == nil)
    }

    @Test func progressionOnlyFrontierStillAllowsEarlierCompleteElements() throws {
        let raw = "Paragraphe déjà lu."
        let element = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(progression: 0.3, totalProgression: 0.3),
            text: .init(highlight: raw)
        )
        let progressionOnlyFrontier = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(progression: 0.5, totalProgression: 0.5)
        )

        let piece = try #require(ReadiumReadingRecapContextExtractor.boundedElement(
            raw, locator: element, firstLocator: nil, lastLocator: nil
        ))
        #expect(piece.text == raw)
        #expect(element.locations.progression! < progressionOnlyFrontier.locations.progression!)
    }

    @Test func suffixBoundingKeepsLocatorAlignedWithReturnedText() throws {
        let text = "0123456789ABCDEFGHIJ"
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!, mediaType: .xhtml,
            locations: .init(totalProgression: 0.3),
            text: .init(after: "Après", before: "Avant", highlight: text)
        )
        let pieces = ReadiumReadingRecapContextExtractor.boundedPieces(
            [.init(text: text, locator: locator)], maximum: 8
        )
        let piece = try #require(pieces.first)
        #expect(piece.text == "CDEFGHIJ")
        #expect(piece.locator.text.highlight == "CDEFGHIJ")
        #expect(piece.locator.text.before?.hasSuffix("0123456789AB") == true)
    }

    @Test func fullBookWindowDistributesTextAcrossTheBook() throws {
        let pieces = (0..<5).map { index in
            let text = "Passage \(index) " + String(repeating: "x", count: 20)
            return ReaderAISourcedExcerpt(
                text: text,
                locator: Locator(
                    href: URL(string: "chapter\(index).xhtml")!,
                    mediaType: .xhtml,
                    locations: .init(totalProgression: Double(index) / 4),
                    text: .init(highlight: text)
                )
            )
        }

        let selected = ReadiumReadingRecapContextExtractor.representativePieces(pieces, maximum: 90)

        #expect(selected.count == 3)
        #expect(selected.first?.text.contains("Passage 0") == true)
        #expect(selected.last?.text.contains("Passage 4") == true)
        #expect(selected.reduce(0) { $0 + $1.text.count } <= 90)
        #expect(selected.allSatisfy { $0.locator.text.highlight == $0.text })
    }
}
