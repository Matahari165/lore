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
}
