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
}
