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

        let stored = try LocatorPersistenceCodec.encode(locator)
        let decoded = try LocatorPersistenceCodec.decode(stored)

        #expect(decoded.locator == locator)
        #expect(!decoded.requiresRewrite)
        #expect(stored.schemaVersion == 1)
    }

    @Test func invalidDataIsRejected() {
        #expect(throws: (any Error).self) {
            try LocatorPersistenceCodec.decode(StoredLocator(data: Data("not json".utf8), schemaVersion: 1))
        }
    }

    @Test func unversionedLocatorIsMigratedCentrally() throws {
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        let decoded = try LocatorPersistenceCodec.decode(
            StoredLocator(data: try locator.jsonData(), schemaVersion: nil)
        )
        #expect(decoded.locator == locator)
        #expect(decoded.requiresRewrite)
    }

    @Test func futureSchemaIsRejectedWithoutDecoding() throws {
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        #expect(throws: ReaderError.self) {
            try LocatorPersistenceCodec.decode(
                StoredLocator(data: try locator.jsonData(), schemaVersion: 99)
            )
        }
    }
}
