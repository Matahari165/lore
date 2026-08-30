import Foundation
import ReadiumShared
import Testing
@testable import Lore

struct LocatorJSONCodecTests {
    @Test func roundTripPreservesCompleteLocator() throws {
        let locator = Locator(
            href: URL(string: "chapter-2.xhtml")!,
            mediaType: .xhtml,
            title: "Deuxième chapitre",
            locations: .init(
                fragments: ["paragraph-7"],
                progression: 0.42,
                totalProgression: 0.31,
                position: 18
            ),
            text: .init(after: "après", before: "avant", highlight: "passage")
        )

        let decoded = try LocatorJSONCodec.decode(LocatorJSONCodec.encode(locator))

        #expect(decoded == locator)
    }

    @Test func invalidDataIsRejected() {
        #expect(throws: (any Error).self) {
            try LocatorJSONCodec.decode(Data("not json".utf8))
        }
    }
}
