import Foundation
import ReadiumShared
import Testing
@testable import Lore

struct HighlightLocatorCodecTests {
    @Test func roundTripPreservesCompleteSelectionLocator() throws {
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            title: "Chapitre",
            locations: .init(fragments: ["p4"], progression: 0.4, totalProgression: 0.2, position: 8),
            text: .init(after: " après", before: "avant ", highlight: "passage")
        )

        let stored = try HighlightLocatorCodec.encode(locator)
        #expect(stored.schemaVersion == 1)
        #expect(try HighlightLocatorCodec.decode(stored) == locator)
    }

    @Test func rejectsUnknownVersion() throws {
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        #expect(throws: HighlightStoreError.self) {
            try HighlightLocatorCodec.decode(
                StoredHighlightLocator(data: try locator.jsonData(), schemaVersion: 99)
            )
        }
    }
}
