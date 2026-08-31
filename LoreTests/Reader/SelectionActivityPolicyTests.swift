import Foundation
import ReadiumShared
import Testing
@testable import Lore

struct SelectionActivityPolicyTests {
    @Test func recordsOneInteractionForOneValidSelection() {
        var policy = SelectionActivityPolicy()
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            text: .init(highlight: "Passage")
        )

        let first = policy.shouldRecord(locator)
        let duplicate = policy.shouldRecord(locator)
        #expect(first)
        #expect(!duplicate)
    }

    @Test func ignoresEmptySelectionAndAllowsSelectionAfterNavigation() {
        var policy = SelectionActivityPolicy()
        let empty = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            text: .init(highlight: "   ")
        )
        let valid = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            text: .init(highlight: "Passage")
        )

        let ignored = policy.shouldRecord(empty)
        let first = policy.shouldRecord(valid)
        policy.reset()
        let afterReset = policy.shouldRecord(valid)
        #expect(!ignored)
        #expect(first)
        #expect(afterReset)
    }
}
