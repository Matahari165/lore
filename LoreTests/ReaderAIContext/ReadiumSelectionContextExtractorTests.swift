import Testing
@testable import Lore

struct ReadiumSelectionContextExtractorTests {
    @Test func windowKeepsSelectionAndBothSidesWithinTheLimit() {
        let result = ReaderAIContextWindowing.make(
            chapterText: String(repeating: "avant ", count: 800) + "passage central" + String(repeating: " après", count: 800),
            selectedText: "passage central",
            beforeLimit: 30,
            afterLimit: 30,
            totalLimit: 70
        )

        #expect(result?.selectedText == "passage central")
        #expect(result?.beforeText.count == 30)
        #expect(result?.afterText.count == 28)
        #expect((result?.beforeText.count ?? 0) + (result?.selectedText.count ?? 0) + (result?.afterText.count ?? 0) <= 70)
    }

    @Test func normalizationAllowsSelectionAcrossWhitespaceVariants() {
        let result = ReaderAIContextWindowing.make(
            chapterText: "Avant\n\nle passage   important\nAprès",
            selectedText: "le passage important"
        )

        #expect(result?.selectedText == "le passage important")
        #expect(result?.beforeText == "Avant")
        #expect(result?.afterText == "Après")
    }

    @Test func beforeHintSelectsTheMatchingOccurrence() {
        let result = ReaderAIContextWindowing.make(
            chapterText: "premier passage puis autre contexte passage suite",
            selectedText: "passage",
            beforeHint: "autre contexte"
        )

        #expect(result?.beforeText == "premier passage puis autre contexte")
        #expect(result?.afterText == "suite")
    }

    @Test func fallbackNeverInventsContext() {
        let result = ReaderAIContextWindowing.fallback(
            before: "contexte connu",
            selected: "passage",
            after: "suite connue",
            beforeLimit: 100,
            afterLimit: 100,
            totalLimit: 100
        )

        #expect(result?.beforeText == "contexte connu")
        #expect(result?.selectedText == "passage")
        #expect(result?.afterText == "suite connue")
    }

    @Test func emptySelectionHasNoWindow() {
        #expect(ReaderAIContextWindowing.make(chapterText: "texte", selectedText: "") == nil)
        #expect(ReaderAIContextWindowing.fallback(before: "avant", selected: "   ", after: "après") == nil)
    }
}
